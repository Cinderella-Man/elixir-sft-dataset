  test "sliding window counts only recently seen distinct members", %{sc: sc} do
    # Time 0: u1, u2
    SlidingUniqueCounter.add(sc, "k", "u1")
    SlidingUniqueCounter.add(sc, "k", "u2")

    # Time 600: u3, u4
    Clock.advance(600)
    SlidingUniqueCounter.add(sc, "k", "u3")
    SlidingUniqueCounter.add(sc, "k", "u4")

    # Time 1_050: u1/u2 (bucket at t=0) have expired, u3/u4 remain
    Clock.advance(450)
    assert 2 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end