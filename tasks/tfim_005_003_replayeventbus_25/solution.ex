  test "history_ttl_ms defaults to 3_600_000 ms when the option is omitted" do
    {:ok, bus} =
      ReplayEventBus.start_link(
        clock: &Clock.now/0,
        default_history_size: 10,
        cleanup_interval_ms: :infinity
      )

    ReplayEventBus.publish(bus, "t", :e)

    # Aged exactly the default TTL: retained (only strictly older is dropped).
    Clock.advance(3_600_000)
    assert [:e] = ReplayEventBus.history(bus, "t")

    # One ms past the default TTL: dropped lazily on the next read.
    Clock.advance(1)
    assert [] = ReplayEventBus.history(bus, "t")
  end