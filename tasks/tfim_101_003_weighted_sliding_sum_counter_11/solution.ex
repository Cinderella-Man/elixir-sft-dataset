  test "different keys are completely independent", %{sc: sc} do
    SlidingSum.add(sc, "a", 3)
    SlidingSum.add(sc, "b", 7)

    assert 3 == SlidingSum.sum(sc, "a", 1_000)
    assert 7 == SlidingSum.sum(sc, "b", 1_000)
  end