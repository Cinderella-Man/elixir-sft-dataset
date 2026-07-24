# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule ReplayEventBus do
  @moduledoc """
  An in-process pub/sub event bus with per-topic bounded replay history.

  Each topic retains the last N events (bounded by count, and independently
  by age via a TTL).  A new subscriber may ask to receive the last K events
  at subscription time, before live delivery begins.  Because the subscribe
  handler runs inside a single GenServer call, replay-and-then-register is
  atomic with respect to other publishes — no event can be missed or
  duplicated between replay and live.

  State:

      %{
        topics: %{
          topic => %{
            # list of {ts_ms, event}, oldest first
            history: [],
            history_size: non_neg_integer,
            # list of %{ref, pid}, oldest subscription first
            subs: []
          }
        },
        monitors: %{ref => {pid, topic}},
        clock, default_history_size, history_ttl_ms, cleanup_interval_ms
      }

  ## Options

    * `:name`                  – optional process registration
    * `:default_history_size`  – default retained events per topic (default 100)
    * `:history_ttl_ms`        – retention age limit (default 3_600_000)
    * `:clock`                 – `(-> integer())` monotonic time in ms
    * `:cleanup_interval_ms`   – periodic sweep interval (default 60_000)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc "Subscribes `pid` to `topic`, optionally replaying buffered events. Returns `{:ok, ref}`."
  @spec subscribe(GenServer.server(), String.t(), pid(), keyword()) :: {:ok, reference()}
  def subscribe(server, topic, pid, opts \\ [])
      when is_binary(topic) and is_pid(pid) and is_list(opts) do
    GenServer.call(server, {:subscribe, topic, pid, opts})
  end

  @spec unsubscribe(GenServer.server(), String.t(), reference()) :: :ok
  def unsubscribe(server, topic, ref), do: GenServer.call(server, {:unsubscribe, topic, ref})

  @spec publish(GenServer.server(), String.t(), term()) :: :ok
  def publish(server, topic, event) when is_binary(topic) do
    GenServer.call(server, {:publish, topic, event})
  end

  @spec history(GenServer.server(), String.t()) :: [term()]
  def history(server, topic) when is_binary(topic) do
    GenServer.call(server, {:history, topic})
  end

  @spec set_history_size(GenServer.server(), String.t(), non_neg_integer()) :: :ok
  def set_history_size(server, topic, size)
      when is_binary(topic) and is_integer(size) and size >= 0 do
    GenServer.call(server, {:set_history_size, topic, size})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, 60_000)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       topics: %{},
       monitors: %{},
       clock: clock,
       default_history_size: Keyword.get(opts, :default_history_size, 100),
       history_ttl_ms: Keyword.get(opts, :history_ttl_ms, 3_600_000),
       cleanup_interval_ms: cleanup_interval
     }}
  end

  @impl true
  def handle_call({:subscribe, topic, pid, sub_opts}, _from, state) do
    now = state.clock.()
    replay = Keyword.get(sub_opts, :replay, :none)

    topic_state =
      state.topics
      |> Map.get(topic, fresh_topic(state.default_history_size))
      |> evict_expired(now, state.history_ttl_ms)

    # Send replay events BEFORE registering, preserving oldest→newest order.
    replay_events(topic_state.history, replay, pid, topic)

    monitor_ref = Process.monitor(pid)

    new_topic_state = %{
      topic_state
      | subs: topic_state.subs ++ [%{ref: monitor_ref, pid: pid}]
    }

    # A fresh `Process.monitor/1` ref per subscribe: the key can never
    # pre-exist, and each ref guards exactly the one topic it was minted for.
    monitors = Map.put(state.monitors, monitor_ref, {pid, topic})

    new_state = %{
      state
      | topics: Map.put(state.topics, topic, new_topic_state),
        monitors: monitors
    }

    {:reply, {:ok, monitor_ref}, new_state}
  end

  def handle_call({:unsubscribe, topic, ref}, _from, state) do
    new_state = remove_ref_from_topic(state, topic, ref)
    {:reply, :ok, new_state}
  end

  def handle_call({:publish, topic, event}, _from, state) do
    now = state.clock.()

    topic_state =
      state.topics
      |> Map.get(topic, fresh_topic(state.default_history_size))
      |> evict_expired(now, state.history_ttl_ms)

    # Deliver live to all current subscribers
    Enum.each(topic_state.subs, fn %{pid: pid} ->
      send(pid, {:event, topic, event})
    end)

    # Append to history, enforce count bound
    new_history =
      (topic_state.history ++ [{now, event}])
      |> Enum.take(-topic_state.history_size)

    new_topic_state = %{topic_state | history: new_history}

    {:reply, :ok, %{state | topics: Map.put(state.topics, topic, new_topic_state)}}
  end

  def handle_call({:history, topic}, _from, state) do
    now = state.clock.()

    case Map.get(state.topics, topic) do
      nil ->
        {:reply, [], state}

      t ->
        fresh = evict_expired(t, now, state.history_ttl_ms)
        events = Enum.map(fresh.history, fn {_ts, evt} -> evt end)
        {:reply, events, %{state | topics: Map.put(state.topics, topic, fresh)}}
    end
  end

  def handle_call({:set_history_size, topic, size}, _from, state) do
    topic_state =
      state.topics
      |> Map.get(topic, fresh_topic(state.default_history_size))
      |> Map.put(:history_size, size)

    # Trim existing history to new size.
    trimmed = Enum.take(topic_state.history, -size)
    new_topic_state = %{topic_state | history: trimmed}

    {:reply, :ok, %{state | topics: Map.put(state.topics, topic, new_topic_state)}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {{_pid, topic}, monitors} ->
        new_topics =
          case Map.get(state.topics, topic) do
            nil ->
              state.topics

            t ->
              Map.put(state.topics, topic, %{t | subs: Enum.reject(t.subs, &(&1.ref == ref))})
          end

        {:noreply, %{state | topics: new_topics, monitors: monitors}}
    end
  end

  def handle_info(:cleanup, state) do
    now = state.clock.()

    new_topics =
      Enum.reduce(state.topics, %{}, fn {name, t}, acc ->
        fresh = evict_expired(t, now, state.history_ttl_ms)

        # Drop topics with empty history AND no subscribers.
        if fresh.history == [] and fresh.subs == [] do
          acc
        else
          Map.put(acc, name, fresh)
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | topics: new_topics}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Replay selection
  # ---------------------------------------------------------------------------

  # history is oldest-first list of {ts, event}.
  defp replay_events(_history, :none, _pid, _topic), do: :ok

  defp replay_events(history, :all, pid, topic) do
    Enum.each(history, fn {_ts, evt} -> send(pid, {:event, topic, evt}) end)
  end

  defp replay_events(history, n, pid, topic) when is_integer(n) and n > 0 do
    # Enum.take(-n) grabs the n last elements in oldest-first order.
    history
    |> Enum.take(-n)
    |> Enum.each(fn {_ts, evt} -> send(pid, {:event, topic, evt}) end)
  end

  defp replay_events(_, _, _, _), do: :ok

  # ---------------------------------------------------------------------------
  # Topic state helpers
  # ---------------------------------------------------------------------------

  defp fresh_topic(default_size), do: %{history: [], history_size: default_size, subs: []}

  # Drop entries older than TTL.  history is oldest-first, so we can stop at
  # the first non-expired entry.
  defp evict_expired(t, now, ttl_ms) do
    cutoff = now - ttl_ms

    live =
      Enum.drop_while(t.history, fn {ts, _evt} -> ts < cutoff end)

    %{t | history: live}
  end

  defp remove_ref_from_topic(state, topic, ref) do
    case Map.get(state.topics, topic) do
      nil ->
        state

      t ->
        new_subs = Enum.reject(t.subs, &(&1.ref == ref))
        topics = Map.put(state.topics, topic, %{t | subs: new_subs})

        # Each ref guards exactly one topic (see subscribe), so removing the
        # subscription always retires the whole monitor.
        monitors =
          if Map.has_key?(state.monitors, ref) do
            Process.demonitor(ref, [:flush])
            Map.delete(state.monitors, ref)
          else
            state.monitors
          end

        %{state | topics: topics, monitors: monitors}
    end
  end

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(ms) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :cleanup, ms)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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

  # -------------------------------------------------------
  # Process registration via :name
  # -------------------------------------------------------

  test "the :name option registers the bus and the whole API works through it" do
    name = :"replay_bus_#{System.pid()}_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      ReplayEventBus.start_link(
        name: name,
        clock: &Clock.now/0,
        default_history_size: 10,
        history_ttl_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    # The name must be a real process registration, not merely an init arg.
    assert Process.whereis(name) == pid

    # Every public function accepts the registered name as the server.
    assert :ok = ReplayEventBus.publish(name, "t", :a)
    {:ok, ref} = ReplayEventBus.subscribe(name, "t", self(), replay: :all)
    assert [:a] = drain("t")

    assert :ok = ReplayEventBus.publish(name, "t", :b)
    assert [:b] = drain("t")
    assert [:a, :b] = ReplayEventBus.history(name, "t")

    assert :ok = ReplayEventBus.set_history_size(name, "t", 1)
    assert [:b] = ReplayEventBus.history(name, "t")

    assert :ok = ReplayEventBus.unsubscribe(name, "t", ref)
    assert :ok = ReplayEventBus.publish(name, "t", :c)
    assert [] = drain("t")
  end

  # -------------------------------------------------------
  # Automatic periodic sweep
  # -------------------------------------------------------

  # A topic whose retained events have all aged past the TTL and that has no
  # subscribers is dropped by the periodic sweep, becoming indistinguishable
  # from a never-seen topic: its per-topic size override is gone and the
  # bus-wide default governs again. Probing for that transition is the only
  # public-API signal that a sweep ran without anyone triggering it.
  defp swept_before?(bus, topic, deadline) do
    ReplayEventBus.publish(bus, topic, 1)
    ReplayEventBus.publish(bus, topic, 2)
    swept? = ReplayEventBus.history(bus, topic) == [1, 2]

    # Age the probe's own events so a later sweep can drop the topic again.
    Clock.advance(15_000)

    cond do
      swept? -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> swept_before?(bus, topic, deadline)
    end
  end

  test "periodic sweep fires on its own at the configured interval" do
    # TODO
  end
end
```
