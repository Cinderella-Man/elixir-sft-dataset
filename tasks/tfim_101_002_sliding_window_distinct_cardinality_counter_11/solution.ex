  test "distinct_count drops to zero once all observations expire", %{sc: sc} do
    for m <- ["u1", "u2", "u3", "u4"] do
      SlidingUniqueCounter.add(sc, "k", m)
    end

    Clock.advance(2_000)

    assert 0 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end