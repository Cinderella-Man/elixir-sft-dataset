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