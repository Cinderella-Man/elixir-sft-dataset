# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule EventBus do
  @moduledoc """
  An in-process pub/sub event bus with wildcard topic support.

  Topics are dot-separated strings (e.g. "orders.created").
  A "*" segment in a subscription pattern matches exactly one segment.
  """

  use GenServer

  # ── Client API ──────────────────────────────────────────────

  @doc "Starts the EventBus. Accepts a `:name` option for registration."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc "Subscribes `pid` to `topic`. Returns `{:ok, ref}`."
  @spec subscribe(GenServer.server(), String.t(), pid()) ::
          {:ok, reference()}
  def subscribe(server, topic, pid) do
    GenServer.call(server, {:subscribe, topic, pid})
  end

  @doc "Removes the subscription identified by `ref` from `topic`."
  @spec unsubscribe(GenServer.server(), String.t(), reference()) ::
          :ok
  def unsubscribe(server, topic, ref) do
    GenServer.call(server, {:unsubscribe, topic, ref})
  end

  @doc "Publishes `event` to all subscribers matching `topic`."
  @spec publish(GenServer.server(), String.t(), term()) :: :ok
  def publish(server, topic, event) do
    GenServer.call(server, {:publish, topic, event})
  end

  # ── Server Callbacks ────────────────────────────────────────

  @impl true
  def init(_opts) do
    # topics: %{topic_pattern => %{ref => pid}}
    # refs:   %{ref => {pid, topic_pattern}}
    # pids:   %{pid => MapSet.t(ref)}
    {:ok, %{topics: %{}, refs: %{}, pids: %{}}}
  end

  @impl true
  def handle_call({:subscribe, topic, pid}, _from, state) do
    ref = Process.monitor(pid)

    topics =
      Map.update(
        state.topics,
        topic,
        %{ref => pid},
        &Map.put(&1, ref, pid)
      )

    refs = Map.put(state.refs, ref, {pid, topic})

    pids =
      Map.update(
        state.pids,
        pid,
        MapSet.new([ref]),
        &MapSet.put(&1, ref)
      )

    {:reply, {:ok, ref}, %{state | topics: topics, refs: refs, pids: pids}}
  end

  def handle_call({:unsubscribe, topic, ref}, _from, state) do
    {:reply, :ok, drop_subscription(state, topic, ref)}
  end

  def handle_call({:publish, topic, event}, _from, state) do
    message = {:event, topic, event}

    Enum.each(state.topics, fn {pattern, subs} ->
      if topic_matches?(pattern, topic) do
        Enum.each(subs, fn {_ref, pid} ->
          send(pid, message)
        end)
      end
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, down_ref, :process, pid, _reason}, state) do
    case Map.fetch(state.pids, pid) do
      {:ok, ref_set} ->
        Enum.each(ref_set, fn r ->
          if r != down_ref do
            Process.demonitor(r, [:flush])
          end
        end)

        state =
          Enum.reduce(ref_set, state, fn r, acc ->
            case Map.fetch(acc.refs, r) do
              {:ok, {_pid, topic}} ->
                drop_subscription_entry(acc, topic, r)

              :error ->
                acc
            end
          end)

        {:noreply, %{state | pids: Map.delete(state.pids, pid)}}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Internal Helpers ────────────────────────────────────────

  defp drop_subscription(state, topic, ref) do
    case Map.fetch(state.refs, ref) do
      {:ok, {pid, ^topic}} ->
        Process.demonitor(ref, [:flush])
        state = drop_subscription_entry(state, topic, ref)
        clean_pid_refs(state, pid, ref)

      _ ->
        state
    end
  end

  defp clean_pid_refs(state, pid, ref) do
    case Map.fetch(state.pids, pid) do
      {:ok, set} ->
        new_set = MapSet.delete(set, ref)

        if MapSet.size(new_set) == 0 do
          %{state | pids: Map.delete(state.pids, pid)}
        else
          %{state | pids: Map.put(state.pids, pid, new_set)}
        end

      :error ->
        state
    end
  end

  defp drop_subscription_entry(state, topic, ref) do
    refs = Map.delete(state.refs, ref)

    topics =
      case Map.fetch(state.topics, topic) do
        {:ok, subs} ->
          new_subs = Map.delete(subs, ref)

          if map_size(new_subs) == 0 do
            Map.delete(state.topics, topic)
          else
            Map.put(state.topics, topic, new_subs)
          end

        :error ->
          state.topics
      end

    %{state | topics: topics, refs: refs}
  end

  defp topic_matches?(pattern, topic) do
    p_parts = String.split(pattern, ".")
    t_parts = String.split(topic, ".")

    length(p_parts) == length(t_parts) and
      segments_match?(p_parts, t_parts)
  end

  defp segments_match?([], []), do: true
  defp segments_match?(["*" | pr], [_ | tr]), do: segments_match?(pr, tr)
  defp segments_match?([s | pr], [s | tr]), do: segments_match?(pr, tr)
  defp segments_match?(_, _), do: false
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule EventBusTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = EventBus.start_link([])
    %{bus: pid}
  end

  # -------------------------------------------------------
  # Basic subscribe / publish
  # -------------------------------------------------------

  test "subscriber receives published event", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "orders.created", self())

    EventBus.publish(bus, "orders.created", %{id: 1})

    assert_receive {:event, "orders.created", %{id: 1}}, 500
  end

  test "subscriber does not receive events for other topics", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "orders.created", self())

    EventBus.publish(bus, "orders.updated", %{id: 1})

    refute_receive {:event, "orders.updated", _}, 200
  end

  test "multiple subscribers all receive the event", %{bus: bus} do
    # Spawn two helper processes that forward events back to us
    parent = self()

    sub1 =
      spawn_link(fn ->
        receive do
          msg -> send(parent, {:sub1, msg})
        end
      end)

    sub2 =
      spawn_link(fn ->
        receive do
          msg -> send(parent, {:sub2, msg})
        end
      end)

    {:ok, _} = EventBus.subscribe(bus, "topic.a", sub1)
    {:ok, _} = EventBus.subscribe(bus, "topic.a", sub2)

    EventBus.publish(bus, "topic.a", :hello)

    assert_receive {:sub1, {:event, "topic.a", :hello}}, 500
    assert_receive {:sub2, {:event, "topic.a", :hello}}, 500
  end

  # -------------------------------------------------------
  # Wildcard topics
  # -------------------------------------------------------

  test "wildcard * matches a single segment", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "orders.*", self())

    EventBus.publish(bus, "orders.created", :e1)
    EventBus.publish(bus, "orders.updated", :e2)

    assert_receive {:event, "orders.created", :e1}, 500
    assert_receive {:event, "orders.updated", :e2}, 500
  end

  test "wildcard * does not match zero segments", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "orders.*", self())

    EventBus.publish(bus, "orders", :nope)

    refute_receive {:event, "orders", _}, 200
  end

  test "wildcard * does not match multiple segments", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "orders.*", self())

    EventBus.publish(bus, "orders.items.created", :nope)

    refute_receive {:event, "orders.items.created", _}, 200
  end

  test "*.* matches any two-segment topic", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "*.*", self())

    EventBus.publish(bus, "orders.created", :e1)
    EventBus.publish(bus, "users.deleted", :e2)

    assert_receive {:event, "orders.created", :e1}, 500
    assert_receive {:event, "users.deleted", :e2}, 500

    # Should NOT match single or triple segments
    EventBus.publish(bus, "orders", :nope)
    EventBus.publish(bus, "a.b.c", :nope2)

    refute_receive {:event, "orders", _}, 200
    refute_receive {:event, "a.b.c", _}, 200
  end

  test "wildcard in the middle: orders.*.completed", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "orders.*.completed", self())

    EventBus.publish(bus, "orders.42.completed", :yes)
    EventBus.publish(bus, "orders.99.completed", :also_yes)
    EventBus.publish(bus, "orders.completed", :nope)
    EventBus.publish(bus, "orders.42.shipped", :nope2)

    assert_receive {:event, "orders.42.completed", :yes}, 500
    assert_receive {:event, "orders.99.completed", :also_yes}, 500
    refute_receive {:event, "orders.completed", _}, 200
    refute_receive {:event, "orders.42.shipped", _}, 200
  end

  # -------------------------------------------------------
  # Exact topic does not act as wildcard
  # -------------------------------------------------------

  test "exact subscription only matches exact topic", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "orders.created", self())

    EventBus.publish(bus, "orders.created", :match)
    EventBus.publish(bus, "orders.updated", :no_match)

    assert_receive {:event, "orders.created", :match}, 500
    refute_receive {:event, "orders.updated", _}, 200
  end

  # -------------------------------------------------------
  # Unsubscribe
  # -------------------------------------------------------

  test "unsubscribe stops delivery", %{bus: bus} do
    {:ok, ref} = EventBus.subscribe(bus, "t", self())

    EventBus.publish(bus, "t", :before)
    assert_receive {:event, "t", :before}, 500

    :ok = EventBus.unsubscribe(bus, "t", ref)

    EventBus.publish(bus, "t", :after)
    refute_receive {:event, "t", :after}, 200
  end

  test "unsubscribe one subscription doesn't affect another on same topic", %{bus: bus} do
    {:ok, ref1} = EventBus.subscribe(bus, "t", self())
    {:ok, _ref2} = EventBus.subscribe(bus, "t", self())

    :ok = EventBus.unsubscribe(bus, "t", ref1)

    EventBus.publish(bus, "t", :hi)

    # Should receive exactly one copy (from _ref2)
    assert_receive {:event, "t", :hi}, 500
    refute_receive {:event, "t", :hi}, 200
  end

  # -------------------------------------------------------
  # Duplicate subscriptions
  # -------------------------------------------------------

  test "same pid subscribing twice receives event twice", %{bus: bus} do
    {:ok, _ref1} = EventBus.subscribe(bus, "t", self())
    {:ok, _ref2} = EventBus.subscribe(bus, "t", self())

    EventBus.publish(bus, "t", :dup)

    assert_receive {:event, "t", :dup}, 500
    assert_receive {:event, "t", :dup}, 500
  end

  # -------------------------------------------------------
  # Dead process cleanup via Process.monitor
  # -------------------------------------------------------

  test "dead subscriber is automatically cleaned up", %{bus: bus} do
    # TODO
  end

  test "dead process subscriptions across multiple topics are all cleaned up", %{bus: bus} do
    child =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, _} = EventBus.subscribe(bus, "topic.a", child)
    {:ok, _} = EventBus.subscribe(bus, "topic.b", child)
    {:ok, _} = EventBus.subscribe(bus, "wild.*", child)

    send(child, :stop)
    ref = Process.monitor(child)
    assert_receive {:DOWN, ^ref, :process, ^child, _}, 500

    # A publish to a topic matching no subscription is a synchronous no-op; once
    # it returns, the bus has already handled the subscriber's :DOWN message.
    assert :ok = EventBus.publish(bus, "barrier", :sync)

    # Subscribe ourselves to verify we're the only ones getting messages
    {:ok, _} = EventBus.subscribe(bus, "topic.a", self())

    EventBus.publish(bus, "topic.a", :check)

    # We should get exactly one (from our own subscription)
    assert_receive {:event, "topic.a", :check}, 500
    refute_receive {:event, "topic.a", :check}, 200
  end

  # -------------------------------------------------------
  # Mixed wildcard and exact on same publish
  # -------------------------------------------------------

  test "publish matches both exact and wildcard subscribers", %{bus: bus} do
    {:ok, _} = EventBus.subscribe(bus, "orders.created", self())
    {:ok, _} = EventBus.subscribe(bus, "orders.*", self())

    EventBus.publish(bus, "orders.created", :boom)

    # Should receive two copies: one from exact, one from wildcard
    assert_receive {:event, "orders.created", :boom}, 500
    assert_receive {:event, "orders.created", :boom}, 500
  end

  # -------------------------------------------------------
  # subscribe returns a unique ref each time
  # -------------------------------------------------------

  test "each subscription returns a unique ref", %{bus: bus} do
    {:ok, ref1} = EventBus.subscribe(bus, "t", self())
    {:ok, ref2} = EventBus.subscribe(bus, "t", self())
    {:ok, ref3} = EventBus.subscribe(bus, "u", self())

    assert ref1 != ref2
    assert ref2 != ref3
  end

  # -------------------------------------------------------
  # publish to topic with no subscribers is a no-op
  # -------------------------------------------------------

  test "publish to topic with no subscribers does not crash", %{bus: bus} do
    assert :ok = EventBus.publish(bus, "nobody.here", :hello)
  end

  # -------------------------------------------------------
  # Named process registration
  # -------------------------------------------------------

  test "can start with a :name and use that name" do
    {:ok, _pid} = EventBus.start_link(name: :my_bus)

    {:ok, _ref} = EventBus.subscribe(:my_bus, "t", self())
    :ok = EventBus.publish(:my_bus, "t", :named)

    assert_receive {:event, "t", :named}, 500
  end

  test "single * pattern matches exactly one segment", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "*", self())

    EventBus.publish(bus, "orders", :one_seg)
    EventBus.publish(bus, "orders.created", :two_seg)

    assert_receive {:event, "orders", :one_seg}, 500
    refute_receive {:event, "orders.created", _}, 200
  end

  test "dead process with duplicate subscriptions on one topic is fully cleaned", %{bus: bus} do
    child =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, _} = EventBus.subscribe(bus, "t", child)
    {:ok, _} = EventBus.subscribe(bus, "t", child)

    send(child, :stop)
    ref = Process.monitor(child)
    assert_receive {:DOWN, ^ref, :process, ^child, _}, 500

    # Synchronous no-op publish; once it returns, the :DOWN has been handled.
    assert :ok = EventBus.publish(bus, "barrier", :sync)

    {:ok, _} = EventBus.subscribe(bus, "t", self())
    EventBus.publish(bus, "t", :check)

    # Only our single subscription should deliver; the two dead ones are gone.
    assert_receive {:event, "t", :check}, 500
    refute_receive {:event, "t", :check}, 200
  end

  test "two subscriptions on same topic deliver exactly two copies", %{bus: bus} do
    {:ok, _ref1} = EventBus.subscribe(bus, "t", self())
    {:ok, _ref2} = EventBus.subscribe(bus, "t", self())

    EventBus.publish(bus, "t", :dup)

    assert_receive {:event, "t", :dup}, 500
    assert_receive {:event, "t", :dup}, 500
    refute_receive {:event, "t", :dup}, 200
  end

  test "remaining subscription is still cleaned up after a sibling unsubscribe", %{bus: bus} do
    child =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, ref1} = EventBus.subscribe(bus, "t", child)
    {:ok, _ref2} = EventBus.subscribe(bus, "t", child)

    :ok = EventBus.unsubscribe(bus, "t", ref1)

    send(child, :stop)
    ref = Process.monitor(child)
    assert_receive {:DOWN, ^ref, :process, ^child, _}, 500

    # Synchronous no-op publish; once it returns, the :DOWN has been handled.
    assert :ok = EventBus.publish(bus, "barrier", :sync)

    {:ok, _} = EventBus.subscribe(bus, "t", self())
    EventBus.publish(bus, "t", :after_down)

    assert_receive {:event, "t", :after_down}, 500
    refute_receive {:event, "t", :after_down}, 200
  end
end
```
