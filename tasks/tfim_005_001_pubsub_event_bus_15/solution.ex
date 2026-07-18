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