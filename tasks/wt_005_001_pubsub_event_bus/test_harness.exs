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
    child =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, _ref} = EventBus.subscribe(bus, "t", child)

    # Kill the subscriber
    send(child, :stop)
    # Wait for the process to actually be dead
    ref = Process.monitor(child)
    assert_receive {:DOWN, ^ref, :process, ^child, _}, 500

    # Give the EventBus time to process the :DOWN message
    # We do a synchronous call to ensure the :DOWN has been handled
    :sys.get_state(bus)

    # Now publish — nobody should receive it, and it shouldn't crash
    EventBus.publish(bus, "t", :ghost)

    refute_receive {:event, "t", :ghost}, 200
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
    :sys.get_state(bus)

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
end
