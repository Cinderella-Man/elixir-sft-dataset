  test "the same member string under two keys is counted per key", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "a", "shared")
    SlidingUniqueCounter.add(sc, "b", "shared")

    assert 1 = SlidingUniqueCounter.distinct_count(sc, "a", 1_000)
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "b", 1_000)
  end