  test "default_history_size defaults to exactly 100 retained events" do
    # Fresh bus WITHOUT :default_history_size — the documented default (100)
    # must apply. Publish 105 events; history keeps exactly the last 100.
    {:ok, bus} =
      ReplayEventBus.start_link(
        clock: &Clock.now/0,
        history_ttl_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    for i <- 1..105, do: ReplayEventBus.publish(bus, "cap", i)

    assert Enum.to_list(6..105) == ReplayEventBus.history(bus, "cap")
  end