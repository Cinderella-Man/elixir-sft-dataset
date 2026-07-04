  test "ladder clamps at the last entry for strikes beyond its length", %{pl: pl} do
    short_ladder = [1_000, 2_000]

    # Earn strike 1, wait for cooldown, earn strike 2, wait, earn strike 3.
    # Strike 3 should reuse the last ladder value (2_000), not crash.
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, short_ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, short_ladder)

    Clock.advance(2_000)

    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, short_ladder)
    assert {:error, :rate_limited, _, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, short_ladder)

    Clock.advance(3_000)

    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, short_ladder)

    assert {:error, :rate_limited, retry_after, 3} =
             PenaltyLimiter.check(pl, "k", 3, 1_000, short_ladder)

    # Strike 3 reuses the last ladder entry: 2_000
    assert retry_after >= 2_000
    assert retry_after < 10_000
  end