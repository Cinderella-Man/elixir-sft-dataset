  test "multiple amounts are summed within the window", %{sc: sc} do
    SlidingSum.add(sc, "k", 3)
    SlidingSum.add(sc, "k", 4)
    assert 7 == SlidingSum.sum(sc, "k", 1_000)
  end