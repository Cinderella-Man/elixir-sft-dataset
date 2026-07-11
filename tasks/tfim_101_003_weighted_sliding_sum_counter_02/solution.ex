  test "sum is zero for a key that has had nothing added", %{sc: sc} do
    assert 0 == SlidingSum.sum(sc, "new_key", 1_000)
  end