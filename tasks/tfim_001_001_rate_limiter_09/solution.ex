  test "works with very large window", %{rl: rl} do
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 86_400_000)
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "k", 1, 86_400_000)

    Clock.advance(86_400_001)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 86_400_000)
  end