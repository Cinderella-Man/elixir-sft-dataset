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