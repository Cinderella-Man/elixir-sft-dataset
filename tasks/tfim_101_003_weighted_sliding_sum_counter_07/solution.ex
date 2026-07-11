  test "amounts outside the window are not included", %{sc: sc} do
    SlidingSum.add(sc, "k", 5)
    Clock.advance(1_001)
    assert 0 == SlidingSum.sum(sc, "k", 1_000)
  end