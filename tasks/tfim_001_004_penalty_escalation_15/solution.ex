  test "a rejected request never occupies a window slot", %{pl: pl} do
    ladder = [1]

    # Three allowed requests at staggered times fill the window (max 3).
    assert {:ok, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    Clock.advance(100)
    assert {:ok, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    Clock.advance(100)
    assert {:ok, 0} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # A rejection at t=300 must NOT be stored as a window timestamp.
    Clock.advance(100)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Advance until only the first entry (t=0) has expired. Had the rejection
    # consumed a slot, the window would still be full and this would reject;
    # because it did not, exactly one fresh slot is available.
    Clock.advance(701)
    assert {:ok, 0} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
  end