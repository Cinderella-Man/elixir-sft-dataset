  test "distinct_count is zero for a key that has never been added", %{sc: sc} do
    assert 0 = SlidingUniqueCounter.distinct_count(sc, "new_key", 1_000)
  end