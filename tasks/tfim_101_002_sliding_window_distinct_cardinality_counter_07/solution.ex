  test "members observed only outside the window are not counted", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "k", "u1")

    # Advance past the window
    Clock.advance(1_001)

    assert 0 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end