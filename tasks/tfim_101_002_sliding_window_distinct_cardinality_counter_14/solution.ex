  test "expiring one key does not affect another", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "a", "u1")

    Clock.advance(500)
    SlidingUniqueCounter.add(sc, "b", "u1")

    # Advance so "a" expires but "b" is still in window
    Clock.advance(600)

    assert 0 = SlidingUniqueCounter.distinct_count(sc, "a", 1_000)
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "b", 1_000)
  end