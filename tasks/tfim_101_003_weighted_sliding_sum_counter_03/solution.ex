  test "a single amount is summed within the window", %{sc: sc} do
    SlidingSum.add(sc, "k", 5)
    assert 5 == SlidingSum.sum(sc, "k", 1_000)
  end