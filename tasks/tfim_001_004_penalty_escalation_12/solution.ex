  test "cleanup preserves in-window request history", %{pl: pl, ladder: ladder} do
    # Two of three window slots consumed, no strikes: the key is NOT inert, so
    # a cleanup pass must leave it alone. A cleanup that drops or trims live
    # keys would hand back a fresh allowance here.
    assert {:ok, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:ok, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    Clock.advance(100)
    send(pl, :cleanup)

    # Still the same window: exactly one slot left, then a rejection.
    assert {:ok, 0} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
  end