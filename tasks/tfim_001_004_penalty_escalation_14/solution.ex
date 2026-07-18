  test "an active cooldown is forgiven once a strike decays under it", %{pl: pl} do
    ladder = [1_000, 30_000]

    # Strike 1 at t=0 (cooldown 1_000ms).
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Past that cooldown, still inside the decay window: escalate to strike 2,
    # whose cooldown (30_000ms) far outlasts the decay period (10_000ms).
    Clock.advance(2_000)
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # One full decay period after strike 2: the cooldown (ending at t=32_000) is
    # still nominally active, but a strike has decayed, so it is cancelled and
    # the request is evaluated against the empty window instead of cooling_down.
    Clock.advance(10_000)
    assert {:ok, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Only one strike decayed (2 → 1, not a full reset), so re-offending
    # escalates straight back to strike 2.
    assert {:ok, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:ok, 0} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
  end