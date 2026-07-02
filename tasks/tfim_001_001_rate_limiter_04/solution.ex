  test "allows requests again after the window slides", %{rl: rl} do
    for _ <- 1..3, do: RateLimiter.check(rl, "k", 3, 1_000)
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "k", 3, 1_000)

    # Advance past the window
    Clock.advance(1_001)

    assert {:ok, _remaining} = RateLimiter.check(rl, "k", 3, 1_000)
  end