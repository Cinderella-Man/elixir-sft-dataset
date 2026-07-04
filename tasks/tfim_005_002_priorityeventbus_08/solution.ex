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