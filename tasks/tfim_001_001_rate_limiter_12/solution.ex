  test "an entry exactly window_ms old is no longer active", %{rl: rl} do
    # Three calls at time 0 exhaust the limit.
    assert {:ok, 2} = RateLimiter.check(rl, "k", 3, 1_000)
    assert {:ok, 1} = RateLimiter.check(rl, "k", 3, 1_000)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 3, 1_000)
    assert {:error, :rate_limited, 1_000} = RateLimiter.check(rl, "k", 3, 1_000)

    # At exactly time 1000 the time-0 entries have fallen out of the window
    # (0 > 1000 - 1000 is false), so the window is empty again.
    Clock.advance(1_000)
    assert {:ok, 2} = RateLimiter.check(rl, "k", 3, 1_000)
  end