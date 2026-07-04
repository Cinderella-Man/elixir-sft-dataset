  test "subscriber that ignores the reply times out and counts as ack", %{bus: bus} do
    s_quiet = spawn_sub(:quiet, policy: :ignore)
    s_low = spawn_sub(:low, policy: :ack)

    sub!(bus, "t", s_quiet, 100)
    sub!(bus, "t", s_low, 1)

    t0 = System.monotonic_time(:millisecond)
    assert {:ok, 2} = PriorityEventBus.publish(bus, "t", :evt)
    dt = System.monotonic_time(:millisecond) - t0

    # Timeout is 200ms → low subscriber still got the event after timeout.
    assert dt >= 150
    assert_receive {:got, :quiet, _, _}
    assert_receive {:got, :low, _, _}
  end