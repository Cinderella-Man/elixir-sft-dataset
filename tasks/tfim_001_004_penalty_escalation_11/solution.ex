  test "max_requests of 1 works with penalty ladder", %{pl: pl, ladder: ladder} do
    assert {:ok, 0} = PenaltyLimiter.check(pl, "k", 1, 500, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 1, 500, ladder)
  end