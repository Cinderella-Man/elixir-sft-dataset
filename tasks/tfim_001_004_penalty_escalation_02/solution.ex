  test "allows requests within the limit", %{pl: pl, ladder: ladder} do
    assert {:ok, 2} = PenaltyLimiter.check(pl, "user:1", 3, 1_000, ladder)
    assert {:ok, 1} = PenaltyLimiter.check(pl, "user:1", 3, 1_000, ladder)
    assert {:ok, 0} = PenaltyLimiter.check(pl, "user:1", 3, 1_000, ladder)
  end