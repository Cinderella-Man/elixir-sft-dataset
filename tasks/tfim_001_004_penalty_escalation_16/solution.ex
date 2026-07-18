  test "retry_after reflects window expiry when it exceeds the strike cooldown", %{pl: pl} do
    # The window (10_000ms) dwarfs the first-strike cooldown (1_000ms).
    ladder = [1_000]

    assert {:ok, 2} = PenaltyLimiter.check(pl, "k", 3, 10_000, ladder)
    assert {:ok, 1} = PenaltyLimiter.check(pl, "k", 3, 10_000, ladder)
    assert {:ok, 0} = PenaltyLimiter.check(pl, "k", 3, 10_000, ladder)

    # Oldest entry (t=0) expires at t=10_000; that 10_000ms window wait is larger
    # than the 1_000ms cooldown, so retry_after must be the window figure.
    assert {:error, :rate_limited, retry_after, 1} =
             PenaltyLimiter.check(pl, "k", 3, 10_000, ladder)

    assert retry_after == 10_000
  end