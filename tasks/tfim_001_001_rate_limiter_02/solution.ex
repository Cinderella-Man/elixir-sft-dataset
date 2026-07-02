  test "allows requests within the limit", %{rl: rl} do
    assert {:ok, 2} = RateLimiter.check(rl, "user:1", 3, 1_000)
    assert {:ok, 1} = RateLimiter.check(rl, "user:1", 3, 1_000)
    assert {:ok, 0} = RateLimiter.check(rl, "user:1", 3, 1_000)
  end