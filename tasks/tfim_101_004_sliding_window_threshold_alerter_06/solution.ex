  test "alarm self-clears as events slide out of the window", %{sc: sc} do
    for _ <- 1..3, do: SlidingAlerter.record(sc, "k")
    assert :alarm = SlidingAlerter.status(sc, "k")

    # Advance past the alerting window so all three events expire.
    Clock.advance(1_001)
    assert 0 = SlidingAlerter.count(sc, "k")
    assert :ok = SlidingAlerter.status(sc, "k")
  end