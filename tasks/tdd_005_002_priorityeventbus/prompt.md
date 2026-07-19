# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
