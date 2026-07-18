  test "interleaved adds across keys at different times", %{sc: sc} do
    Clock.set(0)
    SlidingUniqueCounter.add(sc, "x", "x1")

    Clock.set(300)
    SlidingUniqueCounter.add(sc, "y", "y1")
    SlidingUniqueCounter.add(sc, "x", "x2")

    Clock.set(700)
    SlidingUniqueCounter.add(sc, "y", "y2")

    # At t=1100, "x1" (t=0) expired, "x2" still in; both "y" members still in
    Clock.set(1_100)
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "x", 1_000)
    assert 2 = SlidingUniqueCounter.distinct_count(sc, "y", 1_000)
  end