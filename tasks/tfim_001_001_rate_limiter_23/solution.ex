  test "pruning uses the window_ms of the current call not a stored one", %{rl: rl} do
    # Record one timestamp at time 0 under a 1000ms window.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1_000)

    # At time 600 a check with a narrower 500ms window prunes the time-0 entry
    # (0 > 600 - 500 is false), so the request must be allowed. Had the stored
    # 1000ms window governed, the entry would still be active and this would deny.
    Clock.advance(600)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 500)
  end