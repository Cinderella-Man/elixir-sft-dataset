  test "event aged exactly TTL is retained; strictly older is dropped", %{bus: bus} do
    ReplayEventBus.publish(bus, "t", :edge)

    # Age is now exactly the TTL (10_000 ms). Only events OLDER than the TTL
    # are dropped, so the event must still be retained.
    Clock.advance(10_000)
    assert [:edge] = ReplayEventBus.history(bus, "t")

    # One more ms and it is strictly older than the TTL: dropped.
    Clock.advance(1)
    assert [] = ReplayEventBus.history(bus, "t")
  end