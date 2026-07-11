  test "count only includes events within the window", %{sc: sc} do
    SlidingAlerter.record(sc, "k")
    Clock.advance(500)
    SlidingAlerter.record(sc, "k")
    assert 2 = SlidingAlerter.count(sc, "k")

    # Advance so the first event (now 1_100ms old) falls outside the 1_000ms window.
    Clock.advance(600)
    assert 1 = SlidingAlerter.count(sc, "k")
  end