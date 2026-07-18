  test "history/1 reflects TTL eviction", %{bus: bus} do
    ReplayEventBus.publish(bus, "t", :a)
    Clock.advance(5_000)
    ReplayEventBus.publish(bus, "t", :b)
    Clock.advance(6_000)
    # Now :a is 11s old (> 10s TTL), :b is 6s old

    assert [:b] = ReplayEventBus.history(bus, "t")
  end