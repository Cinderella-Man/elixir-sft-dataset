  test "repeated denials never postpone when the original entry frees a slot", %{rl: rl} do
    # One request at time 0 exhausts a limit of 1 per 1000ms.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1_000)

    # Hammer the limited key twice while blocked; neither denial records a ts.
    Clock.advance(500)
    assert {:error, :rate_limited, 500} = RateLimiter.check(rl, "k", 1, 1_000)
    Clock.advance(400)
    assert {:error, :rate_limited, 100} = RateLimiter.check(rl, "k", 1, 1_000)

    # At time 1000 only the time-0 entry mattered; the hammering did not push
    # its expiry forward, so a slot is free.
    Clock.advance(100)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1_000)
  end