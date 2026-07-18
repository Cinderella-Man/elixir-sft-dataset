  test "interleaved increments across keys at different times", %{sc: sc} do
    Clock.set(0)
    SlidingCounter.increment(sc, "x")

    Clock.set(300)
    SlidingCounter.increment(sc, "y")
    SlidingCounter.increment(sc, "x")

    Clock.set(700)
    SlidingCounter.increment(sc, "y")

    # At t=1100, "x" t=0 expired, "x" t=300 still in; both "y" still in
    Clock.set(1_100)
    assert 1 = SlidingCounter.count(sc, "x", 1_000)
    assert 2 = SlidingCounter.count(sc, "y", 1_000)
  end