  test "sliding window sums only recent amounts", %{sc: sc} do
    SlidingSum.add(sc, "k", 2)

    Clock.advance(600)
    SlidingSum.add(sc, "k", 5)

    # At t=1050, the amount from t=0 (bucket 0) has slid out; only the 5 remains.
    Clock.advance(450)
    assert 5 == SlidingSum.sum(sc, "k", 1_000)
  end