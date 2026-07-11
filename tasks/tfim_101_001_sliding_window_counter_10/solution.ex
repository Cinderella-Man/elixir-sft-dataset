  test "expiring one key does not affect another", %{sc: sc} do
    SlidingCounter.increment(sc, "a")

    Clock.advance(500)
    SlidingCounter.increment(sc, "b")

    # Advance so "a" expires but "b" is still in window
    Clock.advance(600)

    assert 0 = SlidingCounter.count(sc, "a", 1_000)
    assert 1 = SlidingCounter.count(sc, "b", 1_000)
  end