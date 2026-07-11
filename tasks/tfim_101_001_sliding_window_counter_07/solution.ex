  test "sliding window counts only recent events", %{sc: sc} do
    # Time 0: 2 increments
    SlidingCounter.increment(sc, "k")
    SlidingCounter.increment(sc, "k")

    # Time 600: 3 more increments
    Clock.advance(600)
    SlidingCounter.increment(sc, "k")
    SlidingCounter.increment(sc, "k")
    SlidingCounter.increment(sc, "k")

    # Time 1_050: first two (from t=0) have expired, last three (from t=600) remain
    Clock.advance(450)
    assert 3 = SlidingCounter.count(sc, "k", 1_000)
  end