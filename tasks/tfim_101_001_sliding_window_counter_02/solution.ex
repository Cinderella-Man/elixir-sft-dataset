  test "count is zero for a key that has never been incremented", %{sc: sc} do
    assert 0 = SlidingCounter.count(sc, "new_key", 1_000)
  end