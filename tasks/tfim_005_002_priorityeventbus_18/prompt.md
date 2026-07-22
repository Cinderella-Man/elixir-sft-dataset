# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule PriorityEventBus do
  @moduledoc """
  An in-process pub/sub bus with priority-ordered, serial, cancellable delivery.

  Unlike standard fan-out pub/sub, `publish/3` walks subscribers in descending
  priority order (ties broken by subscription order) and waits for an
  ack or cancel from each before proceeding to the next.  A high-priority
  subscriber can `cancel/1` to veto delivery to all remaining lower-priority
  subscribers — useful for validators, audit gates, and cache-invalidation
  layers that must run before dependent handlers.

  State:

      %{
        # %{topic => [%{ref, pid, priority, seq}, ...]}  (list, kept sorted)
        topics: %{},
        # %{monitor_ref => {pid, [topic, ...]}} — for :DOWN cleanup without
        # scanning every topic
        monitors: %{},
        # Monotonic counter for tie-breaking within a priority level.
        next_seq: 0,
        delivery_timeout_ms: pos_integer
      }

  ## Options

    * `:name`                 – optional process registration
    * `:delivery_timeout_ms`  – max wait per subscriber for ack/cancel
                                (default 5_000)

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

  @spec subscribe(GenServer.server(), String.t(), pid(), integer()) :: {:ok, reference()}
  def subscribe(server, topic, pid, priority)
      when is_binary(topic) and is_pid(pid) and is_integer(priority) do
    GenServer.call(server, {:subscribe, topic, pid, priority})
  end

  @spec unsubscribe(GenServer.server(), String.t(), reference()) :: :ok
  def unsubscribe(server, topic, ref) when is_binary(topic) and is_reference(ref) do
    GenServer.call(server, {:unsubscribe, topic, ref})
  end

  @spec publish(GenServer.server(), String.t(), term()) :: {:ok, non_neg_integer()}
  def publish(server, topic, event) when is_binary(topic) do
    GenServer.call(server, {:publish, topic, event}, :infinity)
  end

  @spec subscribers(GenServer.server(), String.t()) :: [{reference(), pid(), integer()}]
  def subscribers(server, topic) when is_binary(topic) do
    GenServer.call(server, {:subscribers, topic})
  end

  @doc "Convenience: send an ack to the bus using the `reply_to` from an event."
  @spec ack({pid(), reference()}) :: :ok
  def ack({bus_pid, ref}) when is_pid(bus_pid) and is_reference(ref) do
    send(bus_pid, {:ack, ref})
    :ok
  end

  @doc "Convenience: cancel further delivery using the `reply_to` from an event."
  @spec cancel({pid(), reference()}) :: :ok
  def cancel({bus_pid, ref}) when is_pid(bus_pid) and is_reference(ref) do
    send(bus_pid, {:cancel, ref})
    :ok
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    {:ok,
     %{
       topics: %{},
       monitors: %{},
       next_seq: 0,
       delivery_timeout_ms: Keyword.get(opts, :delivery_timeout_ms, 5_000)
     }}
  end

  @impl true
  def handle_call({:subscribe, topic, pid, priority}, _from, state) do
    ref = Process.monitor(pid)
    seq = state.next_seq

    sub = %{ref: ref, pid: pid, priority: priority, seq: seq}

    existing = Map.get(state.topics, topic, [])
    new_subs_for_topic = insert_sorted(existing, sub)

    monitors =
      Map.update(state.monitors, ref, {pid, [topic]}, fn {p, topics} ->
        {p, Enum.uniq([topic | topics])}
      end)

    new_state = %{
      state
      | topics: Map.put(state.topics, topic, new_subs_for_topic),
        monitors: monitors,
        next_seq: seq + 1
    }

    {:reply, {:ok, ref}, new_state}
  end

  def handle_call({:unsubscribe, topic, ref}, _from, state) do
    new_state = remove_ref_from_topic(state, topic, ref)
    {:reply, :ok, new_state}
  end

  def handle_call({:subscribers, topic}, _from, state) do
    list =
      state.topics
      |> Map.get(topic, [])
      |> Enum.map(fn %{ref: r, pid: p, priority: pri} -> {r, p, pri} end)

    {:reply, list, state}
  end

  def handle_call({:publish, topic, event}, _from, state) do
    subs = Map.get(state.topics, topic, [])
    delivered = deliver_serially(subs, topic, event, state.delivery_timeout_ms, 0)
    {:reply, {:ok, delivered}, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {{_pid, topics}, monitors} ->
        # For a DOWN, remove this ref from every topic it was subscribed to.
        topics_map =
          Enum.reduce(topics, state.topics, fn topic, acc ->
            case Map.get(acc, topic) do
              nil -> acc
              subs -> Map.put(acc, topic, without(subs, ref))
            end
          end)

        {:noreply, %{state | topics: topics_map, monitors: monitors}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Serial delivery with ack/cancel — the core of this module
  # ---------------------------------------------------------------------------

  # Walks the list in order.  For each subscriber:
  #   - Send {:event, topic, event, {self(), unique_ref}}
  #   - Receive {:ack, unique_ref} | {:cancel, unique_ref} | timeout | :DOWN
  #   - :ack / timeout / :DOWN continue; :cancel stops delivery.
  defp deliver_serially([], _topic, _event, _timeout, delivered), do: delivered

  defp deliver_serially([sub | rest], topic, event, timeout, delivered) do
    unique_ref = make_ref()
    reply_to = {self(), unique_ref}

    send(sub.pid, {:event, topic, event, reply_to})

    receive do
      {:ack, ^unique_ref} ->
        deliver_serially(rest, topic, event, timeout, delivered + 1)

      {:cancel, ^unique_ref} ->
        delivered + 1

      # If the subscriber dies mid-publish, its monitor fires; treat as :ack
      # and continue.  We don't consume the :DOWN here — we leave it for
      # the regular handle_info path so the cleanup still runs.
      {:DOWN, _ref, :process, pid, _reason} = down when pid == sub.pid ->
        # Re-queue for normal processing and continue.
        send(self(), down)
        deliver_serially(rest, topic, event, timeout, delivered + 1)
    after
      timeout ->
        deliver_serially(rest, topic, event, timeout, delivered + 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Sorted insert: descending priority, then ascending subscription order (seq).
  defp insert_sorted(list, sub) do
    # Prepend and sort — the list is typically small so this is fine. Every
    # entry carries its own globally-unique monitor ref, so entries can never
    # collide and no dedup or pre-filtering is needed.
    [sub | list]
    |> Enum.sort_by(fn %{priority: p, seq: s} -> {-p, s} end)
  end

  defp without(list, ref), do: Enum.reject(list, &(&1.ref == ref))

  defp remove_ref_from_topic(state, topic, ref) do
    case Map.get(state.topics, topic) do
      nil ->
        state

      subs ->
        new_subs = without(subs, ref)
        topics = Map.put(state.topics, topic, new_subs)

        # Update monitors map: drop topic from this ref's list; demonitor
        # if no topics remain.
        monitors =
          case Map.fetch(state.monitors, ref) do
            {:ok, {pid, topics_list}} ->
              remaining = List.delete(topics_list, topic)

              if remaining == [] do
                Process.demonitor(ref, [:flush])
                Map.delete(state.monitors, ref)
              else
                Map.put(state.monitors, ref, {pid, remaining})
              end

            :error ->
              state.monitors
          end

        %{state | topics: topics, monitors: monitors}
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule PriorityEventBusTest do
  use ExUnit.Case, async: false

  # --- A scripted subscriber that records events and responds with a
  # --- predetermined ack/cancel decision per event. ---

  defmodule ScriptedSub do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def start(opts) do
      GenServer.start(__MODULE__, opts)
    end

    @impl true
    def init(opts) do
      {:ok,
       %{
         test_pid: Keyword.fetch!(opts, :test_pid),
         tag: Keyword.fetch!(opts, :tag),
         # :ack | :cancel | {:sleep, ms_then} where then is :ack|:cancel
         # | {:ignore} to never reply (tests timeout behavior)
         policy: Keyword.get(opts, :policy, :ack),
         received: []
       }}
    end

    @impl true
    def handle_info({:event, topic, event, reply_to}, state) do
      send(state.test_pid, {:got, state.tag, topic, event})
      react(state.policy, reply_to)
      {:noreply, %{state | received: [{topic, event} | state.received]}}
    end

    defp react(:ack, reply_to), do: PriorityEventBus.ack(reply_to)
    defp react(:cancel, reply_to), do: PriorityEventBus.cancel(reply_to)

    defp react({:sleep, ms, then_}, reply_to) do
      Process.sleep(ms)
      react(then_, reply_to)
    end

    defp react(:ignore, _reply_to), do: :ok
  end

  setup do
    {:ok, bus} = PriorityEventBus.start_link(delivery_timeout_ms: 200)
    %{bus: bus}
  end

  defp sub!(bus, topic, pid, priority) do
    {:ok, ref} = PriorityEventBus.subscribe(bus, topic, pid, priority)
    ref
  end

  defp spawn_sub(tag, opts \\ []) do
    {:ok, pid} =
      ScriptedSub.start([test_pid: self(), tag: tag] ++ opts)

    pid
  end

  # Takes the OLDEST delivery notification still sitting in the mailbox, so a
  # sequence of calls reproduces the exact order the bus reached subscribers
  # (unlike a pattern-pinned assert_receive, which can skip ahead).
  defp next_delivered_tag(timeout) do
    receive do
      {:got, tag, _topic, _event} -> tag
    after
      timeout -> flunk("no further delivery arrived within #{timeout}ms")
    end
  end

  # -------------------------------------------------------
  # Basic subscribe / publish / ack
  # -------------------------------------------------------

  test "exact-topic publish delivers to a single subscriber who acks", %{bus: bus} do
    sub = spawn_sub(:a, policy: :ack)
    _ref = sub!(bus, "orders.created", sub, 0)

    assert {:ok, 1} = PriorityEventBus.publish(bus, "orders.created", %{id: 1})
    assert_received {:got, :a, "orders.created", %{id: 1}}
  end

  test "non-matching topic is not delivered (exact match only)", %{bus: bus} do
    sub = spawn_sub(:a)
    _ = sub!(bus, "orders.created", sub, 0)

    # "orders.*" is NOT a wildcard in this module
    assert {:ok, 0} = PriorityEventBus.publish(bus, "orders.updated", %{})
    refute_received {:got, :a, _, _}

    # Verify "*" is also treated as a literal string
    _ = sub!(bus, "*", sub, 0)
    assert {:ok, 0} = PriorityEventBus.publish(bus, "orders.updated", %{})
    refute_received {:got, :a, _, _}
  end

  test "subscribers/2 lists subs sorted by descending priority", %{bus: bus} do
    s1 = spawn_sub(:s1)
    s2 = spawn_sub(:s2)
    s3 = spawn_sub(:s3)

    r1 = sub!(bus, "t", s1, 5)
    r2 = sub!(bus, "t", s2, 10)
    r3 = sub!(bus, "t", s3, 5)

    subs = PriorityEventBus.subscribers(bus, "t")

    # s2 (priority 10) first; then s1 and s3 (priority 5), oldest subscription first
    assert [{^r2, ^s2, 10}, {^r1, ^s1, 5}, {^r3, ^s3, 5}] = subs
  end

  test "subscribers/2 returns [] for a topic with no subscribers", %{bus: bus} do
    assert [] = PriorityEventBus.subscribers(bus, "never.subscribed")

    # After subscribing then unsubscribing, the topic is empty again.
    sub = spawn_sub(:a, policy: :ack)
    ref = sub!(bus, "t", sub, 0)
    assert [{^ref, ^sub, 0}] = PriorityEventBus.subscribers(bus, "t")

    :ok = PriorityEventBus.unsubscribe(bus, "t", ref)
    assert [] = PriorityEventBus.subscribers(bus, "t")
  end

  # -------------------------------------------------------
  # Priority ordering (the defining property)
  # -------------------------------------------------------

  test "delivery order respects descending priority", %{bus: bus} do
    s_low = spawn_sub(:low, policy: :ack)
    s_mid = spawn_sub(:mid, policy: :ack)
    s_high = spawn_sub(:high, policy: :ack)

    # Subscribe in shuffled order to prove the order comes from priority, not
    # subscription order.
    sub!(bus, "t", s_mid, 50)
    sub!(bus, "t", s_low, 10)
    sub!(bus, "t", s_high, 100)

    assert {:ok, 3} = PriorityEventBus.publish(bus, "t", :evt)

    # Messages arrive in the order they were sent by the bus.
    assert_receive {:got, :high, "t", :evt}
    assert_receive {:got, :mid, "t", :evt}
    assert_receive {:got, :low, "t", :evt}
  end

  test "ties within same priority delivered in subscription order", %{bus: bus} do
    s1 = spawn_sub(:s1, policy: :ack)
    s2 = spawn_sub(:s2, policy: :ack)
    s3 = spawn_sub(:s3, policy: :ack)

    sub!(bus, "t", s1, 5)
    sub!(bus, "t", s2, 5)
    sub!(bus, "t", s3, 5)

    PriorityEventBus.publish(bus, "t", :evt)

    assert_receive {:got, :s1, _, _}
    assert_receive {:got, :s2, _, _}
    assert_receive {:got, :s3, _, _}
  end

  test "exact arrival sequence is descending priority then oldest subscription",
       %{bus: bus} do
    mid_a = spawn_sub(:seq_mid_a, policy: :ack)
    low = spawn_sub(:seq_low, policy: :ack)
    high = spawn_sub(:seq_high, policy: :ack)
    mid_b = spawn_sub(:seq_mid_b, policy: :ack)

    # Subscription order deliberately unrelated to priority order; mid_a and
    # mid_b share a priority level, with mid_a subscribed first.
    sub!(bus, "t", mid_a, 5)
    sub!(bus, "t", low, 1)
    sub!(bus, "t", high, 10)
    sub!(bus, "t", mid_b, 5)

    assert {:ok, 4} = PriorityEventBus.publish(bus, "t", :evt)

    # Delivery is serial, so each notification is fully queued before the next
    # subscriber is reached: mailbox order IS delivery order.
    order = [
      next_delivered_tag(1_000),
      next_delivered_tag(1_000),
      next_delivered_tag(1_000),
      next_delivered_tag(1_000)
    ]

    assert [:seq_high, :seq_mid_a, :seq_mid_b, :seq_low] == order
  end

  # -------------------------------------------------------
  # Cancel short-circuits lower priorities (the other defining property)
  # -------------------------------------------------------

  test "high-priority cancel stops delivery to lower priorities", %{bus: bus} do
    s_low = spawn_sub(:low, policy: :ack)
    s_mid = spawn_sub(:mid, policy: :cancel)
    s_high = spawn_sub(:high, policy: :ack)

    sub!(bus, "t", s_low, 1)
    sub!(bus, "t", s_mid, 50)
    sub!(bus, "t", s_high, 100)

    # high (ack) → mid (cancel — stops delivery); low should not be called.
    assert {:ok, 2} = PriorityEventBus.publish(bus, "t", :evt)

    assert_receive {:got, :high, _, _}
    assert_receive {:got, :mid, _, _}
    refute_received {:got, :low, _, _}
  end

  test "cancel from top priority suppresses everyone below", %{bus: bus} do
    s1 = spawn_sub(:s1, policy: :ack)
    s2 = spawn_sub(:s2, policy: :ack)
    s_top = spawn_sub(:top, policy: :cancel)

    sub!(bus, "t", s1, 1)
    sub!(bus, "t", s2, 2)
    sub!(bus, "t", s_top, 100)

    assert {:ok, 1} = PriorityEventBus.publish(bus, "t", :evt)
    assert_receive {:got, :top, _, _}
    refute_received {:got, :s1, _, _}
    refute_received {:got, :s2, _, _}
  end

  test "ack/1 and cancel/1 send the right message and return :ok", %{bus: bus} do
    # Drive ack/1 and cancel/1 through the public convenience helpers directly,
    # observing the effect on delivery counting rather than internal messages.
    s_high = spawn_sub(:high, policy: :ack)
    s_low = spawn_sub(:low, policy: :ack)

    sub!(bus, "t", s_high, 100)
    sub!(bus, "t", s_low, 1)

    assert {:ok, 2} = PriorityEventBus.publish(bus, "t", :evt)
    assert_receive {:got, :high, _, _}
    assert_receive {:got, :low, _, _}

    # Both helpers return :ok for a well-formed reply_to tuple.
    assert :ok = PriorityEventBus.ack({bus, make_ref()})
    assert :ok = PriorityEventBus.cancel({bus, make_ref()})
  end

  # -------------------------------------------------------
  # Ignored subscribers: timeout, don't cancel
  # -------------------------------------------------------

  test "subscriber that ignores the reply times out and counts as ack", %{bus: bus} do
    s_quiet = spawn_sub(:quiet, policy: :ignore)
    s_low = spawn_sub(:low, policy: :ack)

    sub!(bus, "t", s_quiet, 100)
    sub!(bus, "t", s_low, 1)

    t0 = System.monotonic_time(:millisecond)
    assert {:ok, 2} = PriorityEventBus.publish(bus, "t", :evt)
    dt = System.monotonic_time(:millisecond) - t0

    # Timeout is 200ms → low subscriber still got the event after timeout.
    assert dt >= 150
    assert_receive {:got, :quiet, _, _}
    assert_receive {:got, :low, _, _}
  end

  # -------------------------------------------------------
  # Start-up options: registration and the default delivery timeout
  # -------------------------------------------------------

  test "start_link registers the bus under :name and serves the whole API by name" do
    # TODO
  end

  test "default delivery timeout is long enough that a 1s cancel still vetoes" do
    # No :delivery_timeout_ms given → the documented 5_000ms default applies, so
    # a cancel sent one second into the handler is still the live reply and must
    # suppress the lower-priority subscriber.
    {:ok, bus} = PriorityEventBus.start_link([])
    on_exit(fn -> if Process.alive?(bus), do: GenServer.stop(bus) end)

    s_slow = spawn_sub(:default_slow, policy: {:sleep, 1_000, :cancel})
    s_low = spawn_sub(:default_low, policy: :ack)

    sub!(bus, "t", s_slow, 100)
    sub!(bus, "t", s_low, 1)

    t0 = System.monotonic_time(:millisecond)
    assert {:ok, 1} = PriorityEventBus.publish(bus, "t", :evt)
    dt = System.monotonic_time(:millisecond) - t0

    assert_receive {:got, :default_slow, "t", :evt}
    refute_received {:got, :default_low, _, _}

    # It waited for the slow reply rather than timing out early, and returned as
    # soon as the cancel landed rather than sitting out the full timeout.
    assert dt >= 900
    assert dt < 4_000
  end

  # -------------------------------------------------------
  # Unsubscribe
  # -------------------------------------------------------

  test "unsubscribed sub no longer receives events", %{bus: bus} do
    sub = spawn_sub(:a, policy: :ack)
    ref = sub!(bus, "t", sub, 0)

    :ok = PriorityEventBus.unsubscribe(bus, "t", ref)

    assert {:ok, 0} = PriorityEventBus.publish(bus, "t", :evt)
    refute_received {:got, :a, _, _}
  end

  test "one pid with multiple subscriptions gets one event per subscription", %{bus: bus} do
    sub = spawn_sub(:multi, policy: :ack)
    r1 = sub!(bus, "t", sub, 10)
    r2 = sub!(bus, "t", sub, 5)

    assert {:ok, 2} = PriorityEventBus.publish(bus, "t", :evt)

    assert_receive {:got, :multi, _, _}
    assert_receive {:got, :multi, _, _}

    # Unsubscribing one leaves the other working
    :ok = PriorityEventBus.unsubscribe(bus, "t", r1)
    assert {:ok, 1} = PriorityEventBus.publish(bus, "t", :evt2)
    assert_receive {:got, :multi, _, _}
    refute_received {:got, :multi, _, _}

    :ok = PriorityEventBus.unsubscribe(bus, "t", r2)
  end

  # -------------------------------------------------------
  # DOWN cleanup
  # -------------------------------------------------------

  test "dead subscriber is automatically removed across all topics", %{bus: bus} do
    sub = spawn_sub(:d, policy: :ack)
    _ = sub!(bus, "a", sub, 0)
    _ = sub!(bus, "b", sub, 0)

    ref = Process.monitor(sub)
    GenServer.stop(sub, :shutdown)
    assert_receive {:DOWN, ^ref, _, _, _}

    # The bus's own :DOWN is already queued ahead of this call, so by the time
    # it answers, the dead subscriber has been cleaned out of every topic.
    assert [] = PriorityEventBus.subscribers(bus, "a")
    assert [] = PriorityEventBus.subscribers(bus, "b")

    # A publish to either topic now reaches nobody.
    assert {:ok, 0} = PriorityEventBus.publish(bus, "a", :evt)
    assert {:ok, 0} = PriorityEventBus.publish(bus, "b", :evt)
    refute_received {:got, :d, _, _}
  end

  test "in-flight publish on a dying subscriber continues delivery downstream", %{bus: bus} do
    test_pid = self()

    dying =
      spawn(fn ->
        receive do
          {:event, topic, event, _reply_to} ->
            send(test_pid, {:got, :dying, topic, event})
            exit(:boom)
        end
      end)

    s_low = spawn_sub(:low, policy: :ack)

    sub!(bus, "t", dying, 100)
    sub!(bus, "t", s_low, 1)

    # The high-priority subscriber dies mid-publish without replying; the bus
    # must treat it as an ack, still count it, and deliver to the lower sub.
    assert {:ok, 2} = PriorityEventBus.publish(bus, "t", :evt)

    assert_receive {:got, :dying, "t", :evt}
    assert_receive {:got, :low, "t", :evt}
  end

  test "late cancel arriving after the timeout does not suppress lower priority", %{bus: bus} do
    # Timeout is 200ms (setup); slow subscriber replies :cancel only after 400ms,
    # i.e. with a now-stale reply_to ref. That late cancel must not suppress low.
    s_slow = spawn_sub(:slow, policy: {:sleep, 400, :cancel})
    s_low = spawn_sub(:low, policy: :ack)

    sub!(bus, "t", s_slow, 100)
    sub!(bus, "t", s_low, 1)

    assert {:ok, 2} = PriorityEventBus.publish(bus, "t", :evt)

    assert_receive {:got, :slow, "t", :evt}
    assert_receive {:got, :low, "t", :evt}
  end
end
```
