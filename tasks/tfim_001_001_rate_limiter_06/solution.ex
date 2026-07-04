  test "different keys are completely independent", %{rl: rl} do
    # Exhaust key "a"
    for _ <- 1..3, do: RateLimiter.check(rl, "a", 3, 1_000)
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "a", 3, 1_000)

    # Key "b" should be unaffected
    assert {:ok, 2} = RateLimiter.check(rl, "b", 3, 1_000)
    assert {:ok, 1} = RateLimiter.check(rl, "b", 3, 1_000)
    assert {:ok, 0} = RateLimiter.check(rl, "b", 3, 1_000)
  end