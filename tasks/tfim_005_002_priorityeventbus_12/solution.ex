  test "subscribers/2 returns [] for a topic with no subscribers", %{bus: bus} do
    assert [] = PriorityEventBus.subscribers(bus, "never.subscribed")

    # After subscribing then unsubscribing, the topic is empty again.
    sub = spawn_sub(:a, policy: :ack)
    ref = sub!(bus, "t", sub, 0)
    assert [{^ref, ^sub, 0}] = PriorityEventBus.subscribers(bus, "t")

    :ok = PriorityEventBus.unsubscribe(bus, "t", ref)
    assert [] = PriorityEventBus.subscribers(bus, "t")
  end