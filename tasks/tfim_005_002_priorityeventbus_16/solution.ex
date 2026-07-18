  test "late cancel arriving after the timeout does not suppress lower priority", %{bus: bus} do
    # Timeout is 200ms (setup); slow subscriber replies :cancel only after 400ms,
    # i.e. with a now-stale reply_to ref. That late cancel must not suppress low.
    s_slow = spawn_sub(:slow, policy: {:sleep, 400, :cancel})
    s_low = spawn_sub(:low, policy: :ack)

    sub!(bus, "t", s_slow, 100)
    sub!(bus, "t", s_low, 1)

    assert {:ok, 2} = PriorityEventBus.publish(bus, "t", :evt)

    assert_receive {:got, :slow, "t", :evt}
    assert_receive {:got, :low, "t", :evt}
  end