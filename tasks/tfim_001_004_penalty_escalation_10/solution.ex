  test "strikes and cooldowns are per-key", %{pl: pl, ladder: ladder} do
    # Punish key "a"
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "a", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "a", 3, 1_000, ladder)

    # Key "b" should have a clean slate
    assert {:ok, 2} = PenaltyLimiter.check(pl, "b", 3, 1_000, ladder)
    assert {:ok, 1} = PenaltyLimiter.check(pl, "b", 3, 1_000, ladder)
    assert {:ok, 0} = PenaltyLimiter.check(pl, "b", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "b", 3, 1_000, ladder)
  end