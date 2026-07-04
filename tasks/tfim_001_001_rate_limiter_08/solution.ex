  test "max_requests of 1 allows exactly one call", %{rl: rl} do
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 500)
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "k", 1, 500)
  end