  test "rejection during cooldown returns :cooling_down without new strike", %{
    pl: pl,
    ladder: ladder
  } do
    # Burn through the window and earn strike 1
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # With the default ladder the first cooldown (1_000ms) ends at the same
    # moment the window clears, so the two effects cannot be told apart. Use a
    # separate limiter with a longer first cooldown so the window clears while
    # the cooldown is still active.
    {:ok, pl2} = PenaltyLimiter.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)
    long_ladder = [5_000, 30_000]

    for _ <- 1..3, do: PenaltyLimiter.check(pl2, "k", 3, 1_000, long_ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl2, "k", 3, 1_000, long_ladder)

    # Advance past the window (1_001ms) but well within the 5_000ms cooldown.
    Clock.advance(1_500)

    # Should be :cooling_down, strike count stays at 1 (no compounding).
    assert {:error, :cooling_down, retry_after, 1} =
             PenaltyLimiter.check(pl2, "k", 3, 1_000, long_ladder)

    # Cooldown started at t=0, ends at t=5000. We're at t=1500.
    assert retry_after > 3_000 and retry_after <= 5_000

    # Repeated attempts during cooldown should keep strike count at 1.
    for _ <- 1..5 do
      assert {:error, :cooling_down, _, 1} =
               PenaltyLimiter.check(pl2, "k", 3, 1_000, long_ladder)
    end
  end