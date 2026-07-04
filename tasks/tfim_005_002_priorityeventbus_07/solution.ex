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