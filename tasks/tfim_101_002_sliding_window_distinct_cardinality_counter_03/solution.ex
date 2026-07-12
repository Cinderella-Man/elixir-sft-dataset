  test "single member is counted within the window", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "k", "u1")
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end