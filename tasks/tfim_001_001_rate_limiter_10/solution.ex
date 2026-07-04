  test "interleaved operations on multiple keys", %{rl: rl} do
    assert {:ok, 1} = RateLimiter.check(rl, "x", 2, 1_000)
    assert {:ok, 4} = RateLimiter.check(rl, "y", 5, 2_000)
    assert {:ok, 0} = RateLimiter.check(rl, "x", 2, 1_000)
    assert {:ok, 3} = RateLimiter.check(rl, "y", 5, 2_000)

    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "x", 2, 1_000)
    assert {:ok, 2} = RateLimiter.check(rl, "y", 5, 2_000)
  end