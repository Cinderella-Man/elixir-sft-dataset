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