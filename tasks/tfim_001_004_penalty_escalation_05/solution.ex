  test "cooldown elapses and normal requests resume", %{pl: pl, ladder: ladder} do
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Advance past cooldown and window
    Clock.advance(1_500)

    # Now allowed again
    assert {:ok, _} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
  end