  test "default delivery timeout is long enough that a 1s cancel still vetoes" do
    # No :delivery_timeout_ms given → the documented 5_000ms default applies, so
    # a cancel sent one second into the handler is still the live reply and must
    # suppress the lower-priority subscriber.
    {:ok, bus} = PriorityEventBus.start_link([])
    on_exit(fn -> if Process.alive?(bus), do: GenServer.stop(bus) end)

    s_slow = spawn_sub(:default_slow, policy: {:sleep, 1_000, :cancel})
    s_low = spawn_sub(:default_low, policy: :ack)

    sub!(bus, "t", s_slow, 100)
    sub!(bus, "t", s_low, 1)

    t0 = System.monotonic_time(:millisecond)
    assert {:ok, 1} = PriorityEventBus.publish(bus, "t", :evt)
    dt = System.monotonic_time(:millisecond) - t0

    assert_receive {:got, :default_slow, "t", :evt}
    refute_received {:got, :default_low, _, _}

    # It waited for the slow reply rather than timing out early, and returned as
    # soon as the cancel landed rather than sitting out the full timeout.
    assert dt >= 900
    assert dt < 4_000
  end