  test "negative amounts subtract from the running sum", %{sc: sc} do
    SlidingSum.add(sc, "k", 10)
    SlidingSum.add(sc, "k", -3)
    assert 7 == SlidingSum.sum(sc, "k", 1_000)
  end