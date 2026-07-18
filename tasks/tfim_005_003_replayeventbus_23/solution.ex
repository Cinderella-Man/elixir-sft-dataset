  test "cleanup_interval_ms: 1 is a valid interval and the bus keeps serving" do
    {:ok, bus} =
      ReplayEventBus.start_link(
        clock: &Clock.now/0,
        default_history_size: 10,
        history_ttl_ms: 10_000,
        cleanup_interval_ms: 1
      )

    ReplayEventBus.publish(bus, "t", :old)
    Clock.advance(15_000)

    # Give the 1 ms periodic sweep plenty of chances to fire, then confirm the
    # bus is alive and still serving through the public API.
    Process.sleep(50)
    assert Process.alive?(bus)
    assert [] = ReplayEventBus.history(bus, "t")
    assert :ok = ReplayEventBus.publish(bus, "t", :fresh)
    assert [:fresh] = ReplayEventBus.history(bus, "t")
  end