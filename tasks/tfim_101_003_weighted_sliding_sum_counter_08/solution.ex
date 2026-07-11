  test "bucket whose start is within the window is included", %{sc: sc} do
    SlidingSum.add(sc, "k", 5)
    Clock.advance(999)
    assert 5 == SlidingSum.sum(sc, "k", 1_000)
  end