  test "members exactly at the window boundary are counted", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "k", "u1")

    # Advance to just inside the window
    Clock.advance(999)

    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end