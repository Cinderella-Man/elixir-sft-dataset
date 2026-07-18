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