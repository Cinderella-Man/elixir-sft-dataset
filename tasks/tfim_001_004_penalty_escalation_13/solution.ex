  test "cleanup preserves active cooldowns and strike counts", %{pl: pl} do
    long_ladder = [5_000, 30_000]

    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, long_ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, long_ladder)

    # Past the window, inside the 5_000ms cooldown.
    Clock.advance(1_500)
    send(pl, :cleanup)

    # The cooldown must survive the cleanup pass untouched.
    assert {:error, :cooling_down, retry_after, 1} =
             PenaltyLimiter.check(pl, "k", 3, 1_000, long_ladder)

    assert retry_after > 3_000 and retry_after <= 5_000

    # Past the cooldown but well inside the decay period: the strike count
    # must also have survived, so the next violation escalates to strike 2.
    Clock.advance(4_000)
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, long_ladder)

    assert {:error, :rate_limited, retry_after_2, 2} =
             PenaltyLimiter.check(pl, "k", 3, 1_000, long_ladder)

    assert retry_after_2 >= 30_000
  end