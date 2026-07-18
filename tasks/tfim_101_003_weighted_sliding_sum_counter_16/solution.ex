  test "a zero window is legal and follows the inclusive start-time rule", %{sc: sc} do
    SlidingSum.add(sc, "z", 7)

    # window_ms = 0 means cutoff = now; the current bucket starts at 0 = now,
    # which satisfies bucket_start >= now - 0, so the amount is counted.
    assert 7 == SlidingSum.sum(sc, "z", 0)
  end