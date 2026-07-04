  test "sliding window drops old requests correctly", %{rl: rl} do
    # Time 0: first request
    assert {:ok, 2} = RateLimiter.check(rl, "k", 3, 1_000)

    # Time 400: second request
    Clock.advance(400)
    assert {:ok, 1} = RateLimiter.check(rl, "k", 3, 1_000)

    # Time 800: third request
    Clock.advance(400)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 3, 1_000)

    # Time 800: fourth request — rejected
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "k", 3, 1_000)

    # Time 1001: first request (from time 0) has expired, one slot free
    Clock.advance(201)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 3, 1_000)

    # Still blocked (requests from 400 and 800 still in window)
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "k", 3, 1_000)
  end