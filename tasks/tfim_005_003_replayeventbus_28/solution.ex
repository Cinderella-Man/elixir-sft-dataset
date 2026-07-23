  test "periodic sweep fires on its own at the configured interval" do
    {:ok, bus} =
      ReplayEventBus.start_link(
        clock: &Clock.now/0,
        default_history_size: 10,
        history_ttl_ms: 10_000,
        cleanup_interval_ms: 25
      )

    # Per-topic override of 1 keeps history at [2] after two publishes; once a
    # sweep drops the topic, the bus-wide default of 10 keeps both events.
    :ok = ReplayEventBus.set_history_size(bus, "auto", 1)
    ReplayEventBus.publish(bus, "auto", :seed)
    Clock.advance(15_000)

    # Generous bounded deadline: 80x the 25 ms interval.
    deadline = System.monotonic_time(:millisecond) + 2_000
    assert swept_before?(bus, "auto", deadline)
  end