  test "repeated members among distinct ones are deduplicated", %{sc: sc} do
    for m <- ["u1", "u2", "u1", "u3", "u2", "u1"] do
      SlidingUniqueCounter.add(sc, "k", m)
    end

    assert 3 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end