  test "events older than TTL are not replayed", %{bus: bus} do
    ReplayEventBus.publish(bus, "t", :old)

    # Advance past TTL (10_000ms)
    Clock.advance(15_000)

    ReplayEventBus.publish(bus, "t", :fresh)

    {:ok, _} = ReplayEventBus.subscribe(bus, "t", self(), replay: :all)

    assert [:fresh] = drain("t")
  end