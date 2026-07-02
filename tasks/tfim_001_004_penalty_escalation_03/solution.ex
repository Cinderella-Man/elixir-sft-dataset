  test "rejects the request that exceeds the limit and records a strike", %{
    pl: pl,
    ladder: ladder
  } do
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    assert {:error, :rate_limited, retry_after, 1} =
             PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # retry_after must cover both the window expiry and the first-strike cooldown (1_000ms).
    assert retry_after >= 1_000
  end