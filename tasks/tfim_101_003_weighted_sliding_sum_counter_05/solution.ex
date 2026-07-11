  test "float amounts are summed", %{sc: sc} do
    SlidingSum.add(sc, "k", 2.5)
    SlidingSum.add(sc, "k", 1.5)
    assert 4.0 == SlidingSum.sum(sc, "k", 1_000)
  end