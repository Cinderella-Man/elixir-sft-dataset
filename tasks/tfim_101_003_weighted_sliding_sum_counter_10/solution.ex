  test "sum drops to zero once all amounts expire", %{sc: sc} do
    SlidingSum.add(sc, "k", 9)
    Clock.advance(2_000)
    assert 0 == SlidingSum.sum(sc, "k", 1_000)
  end