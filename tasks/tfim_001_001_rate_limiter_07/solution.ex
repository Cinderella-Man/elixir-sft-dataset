  test "retry_after tells the caller how long until a slot opens", %{rl: rl} do
    # Request at time 0
    RateLimiter.check(rl, "k", 1, 1_000)

    # Advance to time 300
    Clock.advance(300)

    assert {:error, :rate_limited, retry_after} =
             RateLimiter.check(rl, "k", 1, 1_000)

    # The earliest request (at time 0) expires at time 1000.
    # We're at time 300, so retry_after should be ~700
    assert retry_after >= 600 and retry_after <= 800
  end