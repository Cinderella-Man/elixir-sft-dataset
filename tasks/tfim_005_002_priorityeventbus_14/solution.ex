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