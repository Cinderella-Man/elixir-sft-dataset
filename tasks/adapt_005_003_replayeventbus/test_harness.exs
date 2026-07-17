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

    # Wait for the subscriber process itself to be gone, then drive the bus
    # through the documented public API while it handles the :DOWN. The bus
    # is linked to this test process, so a bus whose :DOWN handling crashes
    # takes the test down with it; a healthy bus keeps serving publish/3 and
    # history/2. Internal state is deliberately not inspected.
    mref = Process.monitor(task.pid)
    assert_receive {:DOWN, ^mref, :process, _, _}, 1_000

    for _ <- 1..20 do
      assert :ok = ReplayEventBus.publish(bus, "down_sync", :ping)
      Process.sleep(5)
    end

    assert Process.alive?(bus)

    # Publishing to the dead subscriber's topics still works, and the
    # topic's history is preserved (history is per-topic, not per-subscriber).
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

    # history/2 is a synchronous call, so it can only be served after the
    # bus has finished handling the :cleanup sweep queued before it.
    assert [] = ReplayEventBus.history(bus, "t")
  end

  test "cleanup drops topics with empty history and no subscribers", %{bus: bus} do
    # A per-topic history size override is part of the topic entry. Once the
    # sweep drops the topic, it is indistinguishable from a never-seen topic,
    # so the bus-wide default (10) governs the topic again.
    :ok = ReplayEventBus.set_history_size(bus, "t", 3)

    ReplayEventBus.publish(bus, "t", :old)
    Clock.advance(15_000)

    send(bus, :cleanup)

    assert [] = ReplayEventBus.history(bus, "t")

    for i <- 1..15, do: ReplayEventBus.publish(bus, "t", i)

    assert Enum.to_list(6..15) == ReplayEventBus.history(bus, "t")
  end

  test "cleanup keeps topics with subscribers even if history is empty", %{bus: bus} do
    {:ok, _} = ReplayEventBus.subscribe(bus, "t", self())
    :ok = ReplayEventBus.set_history_size(bus, "t", 3)
    # No events published, history empty
    Clock.advance(15_000)

    send(bus, :cleanup)

    assert [] = ReplayEventBus.history(bus, "t")

    # The topic survived the sweep along with its subscriber: live events are
    # still delivered to it, and its per-topic size override still applies.
    for i <- 1..5, do: ReplayEventBus.publish(bus, "t", i)

    assert [1, 2, 3, 4, 5] = drain("t")
    assert [3, 4, 5] = ReplayEventBus.history(bus, "t")
  end

  # -------------------------------------------------------
  # Documented defaults and boundary semantics
  # -------------------------------------------------------

  test "default_history_size defaults to exactly 100 retained events" do
    # Fresh bus WITHOUT :default_history_size — the documented default (100)
    # must apply. Publish 105 events; history keeps exactly the last 100.
    {:ok, bus} =
      ReplayEventBus.start_link(
        clock: &Clock.now/0,
        history_ttl_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    for i <- 1..105, do: ReplayEventBus.publish(bus, "cap", i)

    assert Enum.to_list(6..105) == ReplayEventBus.history(bus, "cap")
  end

  test "replay: 1 delivers exactly the single most recent event", %{bus: bus} do
    for e <- [:a, :b, :c], do: ReplayEventBus.publish(bus, "t", e)

    {:ok, _ref} = ReplayEventBus.subscribe(bus, "t", self(), replay: 1)

    assert [:c] = drain("t")
  end

  test "event aged exactly TTL is retained; strictly older is dropped", %{bus: bus} do
    ReplayEventBus.publish(bus, "t", :edge)

    # Age is now exactly the TTL (10_000 ms). Only events OLDER than the TTL
    # are dropped, so the event must still be retained.
    Clock.advance(10_000)
    assert [:edge] = ReplayEventBus.history(bus, "t")

    # One more ms and it is strictly older than the TTL: dropped.
    Clock.advance(1)
    assert [] = ReplayEventBus.history(bus, "t")
  end

  test "cleanup_interval_ms: 1 is a valid interval and the bus keeps serving" do
    {:ok, bus} =
      ReplayEventBus.start_link(
        clock: &Clock.now/0,
        default_history_size: 10,
        history_ttl_ms: 10_000,
        cleanup_interval_ms: 1
      )

    ReplayEventBus.publish(bus, "t", :old)
    Clock.advance(15_000)

    # Give the 1 ms periodic sweep plenty of chances to fire, then confirm the
    # bus is alive and still serving through the public API.
    Process.sleep(50)
    assert Process.alive?(bus)
    assert [] = ReplayEventBus.history(bus, "t")
    assert :ok = ReplayEventBus.publish(bus, "t", :fresh)
    assert [:fresh] = ReplayEventBus.history(bus, "t")
  end

  test "history/2 returns [] for a topic never published or subscribed", %{bus: bus} do
    assert [] = ReplayEventBus.history(bus, "never.seen.topic")
  end

  test "history_ttl_ms defaults to 3_600_000 ms when the option is omitted" do
    {:ok, bus} =
      ReplayEventBus.start_link(
        clock: &Clock.now/0,
        default_history_size: 10,
        cleanup_interval_ms: :infinity
      )

    ReplayEventBus.publish(bus, "t", :e)

    # Aged exactly the default TTL: retained (only strictly older is dropped).
    Clock.advance(3_600_000)
    assert [:e] = ReplayEventBus.history(bus, "t")

    # One ms past the default TTL: dropped lazily on the next read.
    Clock.advance(1)
    assert [] = ReplayEventBus.history(bus, "t")
  end

  test "set_history_size/3 rejects a negative size via its guard", %{bus: bus} do
    assert_raise FunctionClauseError, fn ->
      ReplayEventBus.set_history_size(bus, "t", -1)
    end
  end
end
