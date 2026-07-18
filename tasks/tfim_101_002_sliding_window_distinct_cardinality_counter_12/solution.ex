  test "different keys are completely independent", %{sc: sc} do
    for m <- ["a1", "a2", "a3"], do: SlidingUniqueCounter.add(sc, "a", m)
    for m <- ["b1", "b2", "b3", "b4", "b5", "b6", "b7"], do: SlidingUniqueCounter.add(sc, "b", m)

    assert 3 = SlidingUniqueCounter.distinct_count(sc, "a", 1_000)
    assert 7 = SlidingUniqueCounter.distinct_count(sc, "b", 1_000)
  end