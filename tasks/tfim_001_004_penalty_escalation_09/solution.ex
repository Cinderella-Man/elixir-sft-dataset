  test "multiple strikes decay one at a time", %{pl: pl, ladder: ladder} do
    # Accumulate 3 strikes
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    Clock.advance(2_000)

    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    Clock.advance(6_000)

    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 3} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Wait exactly one decay period (10_000ms from last strike).
    Clock.advance(10_000)

    # Reoffend — should be strike 3 (one decayed, bringing 3 → 2, then +1 = 3).
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 3} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
  end