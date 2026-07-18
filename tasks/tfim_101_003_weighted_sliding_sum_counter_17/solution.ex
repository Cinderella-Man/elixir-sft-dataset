  test "a bucket starting exactly at the window cutoff is included", %{sc: sc} do
    SlidingSum.add(sc, "edge", 3)
    Clock.set(1_000)

    # cutoff = 1000 - 1000 = 0; the bucket starts at 0 — inclusive boundary.
    assert 3 == SlidingSum.sum(sc, "edge", 1_000)
  end