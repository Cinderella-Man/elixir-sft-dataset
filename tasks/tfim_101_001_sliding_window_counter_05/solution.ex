  test "events outside the window are not counted", %{sc: sc} do
    # Increment at time 0
    SlidingCounter.increment(sc, "k")

    # Advance past the window
    Clock.advance(1_001)

    assert 0 = SlidingCounter.count(sc, "k", 1_000)
  end