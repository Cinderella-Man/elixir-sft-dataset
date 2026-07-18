  test "retry_after is the exact wait until the oldest entry expires", %{rl: rl} do
    # Single request at time 0 under a limit of 1 per 1000ms.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1_000)

    # At time 999 the entry expires in exactly 1ms: max(0 + 1000 - 999, 1) == 1.
    Clock.advance(999)
    assert {:error, :rate_limited, 1} = RateLimiter.check(rl, "k", 1, 1_000)

    # Waiting exactly retry_after_ms must succeed (no calls in between; a denied
    # call records no timestamp, so the window did not move forward).
    Clock.advance(1)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1_000)
  end