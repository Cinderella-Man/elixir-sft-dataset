  test "decay reference advances by a full period rather than resetting to now", %{
    pl: pl,
    ladder: ladder
  } do
    # Strike 1 at t=0.
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Strike 2 at t=2_000 (last-strike reference = 2_000).
    Clock.advance(2_000)
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # t=17_000: 1.5 decay periods after the reference. Exactly one strike decays
    # (2 → 1) and the reference advances to t=12_000, NOT to t=17_000.
    Clock.advance(15_000)
    assert {:ok, _} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # t=22_000: only 5_000ms since that check, but a full 10_000ms since the
    # advanced reference (12_000), so the last strike decays away and the key
    # resets. Re-offending therefore starts again at strike 1, not strike 2.
    Clock.advance(5_000)
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
  end