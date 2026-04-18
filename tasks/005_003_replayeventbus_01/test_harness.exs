defmodule ReplayEventBusTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, bus} =
      ReplayEventBus.start_link(
        clock: &Clock.now/0,
        default_history_size: 10,
        history_ttl_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    %{bus: bus}
  end

  # Collect all events sent to `self()` for `topic`, up to `max` in `timeout` ms.
  defp drain(topic, timeout \\ 50) do
    drain_loop(topic, [], timeout)
  end

  defp drain_loop(topic, acc, timeout) do
    receive do
      {:event, ^topic, evt} -> drain_loop(topic, [evt | acc], timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end

  # -------------------------------------------------------
  # Basic pub/sub without replay
  # -------------------------------------------------------

  test "default subscribe has no replay — only live events", %{bus: bus} do
    ReplayEventBus.publish(bus, "t", :e1)
    ReplayEventBus.publish(bus, "t", :e2)

    {:ok, _ref} = ReplayEventBus.subscribe(bus, "t", self())

    # Past events should NOT arrive
    assert [] = drain("t")

    ReplayEventBus.publish(bus, "t", :e3)
    assert [:e3] = drain("t")
  end

  test "exact topic matching only (no wildcards)", %{bus: bus} do
    {:ok, _} = ReplayEventBus.subscribe(bus, "orders.created", self())
    ReplayEventBus.publish(bus, "orders.updated", :x)

    assert [] = drain("orders.updated")
    assert [] = drain("orders.created")
  end

  # -------------------------------------------------------
  # Replay: :all
  # -------------------------------------------------------

  test "replay: :all delivers every retained event in order", %{bus: bus} do
    for e <- [:a, :b, :c], do: ReplayEventBus.publish(bus, "t", e)

    {:ok, _ref} = ReplayEventBus.subscribe(bus, "t", self(), replay: :all)

    assert [:a, :b, :c] = drain("t")
  end

  # -------------------------------------------------------
  # Replay: N
  # -------------------------------------------------------

  test "replay: N delivers exactly the last N events in order", %{bus: bus} do
    for e <- [:a, :b, :c, :d, :e], do: ReplayEventBus.publish(bus, "t", e)

    {:ok, _ref} = ReplayEventBus.subscribe(bus, "t", self(), replay: 2)

    assert [:d, :e] = drain("t")
  end

  test "replay: N where N exceeds history size yields all events", %{bus: bus} do
    for e <- [:a, :b], do: ReplayEventBus.publish(bus, "t", e)

    {:ok, _ref} = ReplayEventBus.subscribe(bus, "t", self(), replay: 100)

    assert [:a, :b] = drain("t")
  end

  # -------------------------------------------------------
  # Replay + live in correct order
  # -------------------------------------------------------

  test "replayed events arrive before live events, in order", %{bus: bus} do
    for e <- [:a, :b, :c], do: ReplayEventBus.publish(bus, "t", e)

    {:ok, _ref} = ReplayEventBus.subscribe(bus, "t", self(), replay: :all)

    # Now publish one more live
    ReplayEventBus.publish(bus, "t", :d)

    assert [:a, :b, :c, :d] = drain("t")
  end

  # -------------------------------------------------------
  # History bounds: count
  # -------------------------------------------------------

  test "history is bounded by default_history_size", %{bus: bus} do
    for i <- 1..15, do: ReplayEventBus.publish(bus, "t", i)

    # default_history_size is 10 → history keeps the last 10
    assert [6, 7, 8, 9, 10, 11, 12, 13, 14, 15] = ReplayEventBus.history(bus, "t")
  end

  test "set_history_size overrides the default", %{bus: bus} do
    :ok = ReplayEventBus.set_history_size(bus, "t", 3)

    for i <- 1..5, do: ReplayEventBus.publish(bus, "t", i)

    assert [3, 4, 5] = ReplayEventBus.history(bus, "t")
  end

  test "set_history_size to 0 disables history", %{bus: bus} do
    for i <- 1..5, do: ReplayEventBus.publish(bus, "t", i)
    :ok = ReplayEventBus.set_history_size(bus, "t", 0)
    assert [] = ReplayEventBus.history(bus, "t")

    ReplayEventBus.publish(bus, "t", 6)
    assert [] = ReplayEventBus.history(bus, "t")
  end

  # -------------------------------------------------------
  # History bounds: TTL
  # -------------------------------------------------------

  test "events older than TTL are not replayed", %{bus: bus} do
    ReplayEventBus.publish(bus, "t", :old)

    # Advance past TTL (10_000ms)
    Clock.advance(15_000)

    ReplayEventBus.publish(bus, "t", :fresh)

    {:ok, _} = ReplayEventBus.subscribe(bus, "t", self(), replay: :all)

    assert [:fresh] = drain("t")
  end

  test "history/1 reflects TTL eviction", %{bus: bus} do
    ReplayEventBus.publish(bus, "t", :a)
    Clock.advance(5_000)
    ReplayEventBus.publish(bus, "t", :b)
    Clock.advance(6_000)
    # Now :a is 11s old (> 10s TTL), :b is 6s old

    assert [:b] = ReplayEventBus.history(bus, "t")
  end

  # -------------------------------------------------------
  # Atomic replay-then-live
  # -------------------------------------------------------

  test "no event is missed or duplicated between replay and live", %{bus: bus} do
    # Publish 2 events
    ReplayEventBus.publish(bus, "t", :a)
    ReplayEventBus.publish(bus, "t", :b)

    # Subscribe asking for replay
    {:ok, _} = ReplayEventBus.subscribe(bus, "t", self(), replay: :all)

    # Publish one more — should arrive exactly once (live), NOT in replay
    ReplayEventBus.publish(bus, "t", :c)

    # Total: 3 events, each exactly once
    assert [:a, :b, :c] = drain("t")
  end

  # -------------------------------------------------------
  # Monitor-based cleanup on :DOWN
  # -------------------------------------------------------

  test "dead subscriber is removed from all topics; history preserved", %{bus: bus} do
    task =
      Task.async(fn ->
        {:ok, _r1} = ReplayEventBus.subscribe(bus, "a", self())
        {:ok, _r2} = ReplayEventBus.subscribe(bus, "b", self())
        :ready
      end)

    assert :ready = Task.await(task)

    # Task has exited — the bus should clean up on :DOWN
    :sys.get_state(bus)
    state = :sys.get_state(bus)

    for topic <- ["a", "b"] do
      case Map.get(state.topics, topic) do
        nil -> :ok
        t -> assert t.subs == []
      end
    end

    # History from before the subscriber died is still intact
    ReplayEventBus.publish(bus, "a", :survived)
    assert [:survived] = ReplayEventBus.history(bus, "a")
  end

  # -------------------------------------------------------
  # Unsubscribe
  # -------------------------------------------------------

  test "unsubscribe stops live delivery but leaves history intact", %{bus: bus} do
    {:ok, ref} = ReplayEventBus.subscribe(bus, "t", self())

    ReplayEventBus.publish(bus, "t", :a)
    assert [:a] = drain("t")

    :ok = ReplayEventBus.unsubscribe(bus, "t", ref)

    ReplayEventBus.publish(bus, "t", :b)
    assert [] = drain("t")

    # History includes both (publishes always update history)
    assert [:a, :b] = ReplayEventBus.history(bus, "t")
  end

  test "one pid with N subscriptions gets N copies per event", %{bus: bus} do
    {:ok, _r1} = ReplayEventBus.subscribe(bus, "t", self())
    {:ok, _r2} = ReplayEventBus.subscribe(bus, "t", self())

    ReplayEventBus.publish(bus, "t", :x)

    assert [:x, :x] = drain("t")
  end

  # -------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------

  test "cleanup evicts expired history", %{bus: bus} do
    ReplayEventBus.publish(bus, "t", :old)
    Clock.advance(15_000)

    send(bus, :cleanup)
    :sys.get_state(bus)

    assert [] = ReplayEventBus.history(bus, "t")
  end

  test "cleanup drops topics with empty history and no subscribers", %{bus: bus} do
    ReplayEventBus.publish(bus, "t", :old)
    Clock.advance(15_000)

    send(bus, :cleanup)
    :sys.get_state(bus)

    state = :sys.get_state(bus)
    refute Map.has_key?(state.topics, "t")
  end

  test "cleanup keeps topics with subscribers even if history is empty", %{bus: bus} do
    {:ok, _} = ReplayEventBus.subscribe(bus, "t", self())
    # No events published, history empty
    Clock.advance(15_000)

    send(bus, :cleanup)
    :sys.get_state(bus)

    state = :sys.get_state(bus)
    assert Map.has_key?(state.topics, "t")
  end
end
