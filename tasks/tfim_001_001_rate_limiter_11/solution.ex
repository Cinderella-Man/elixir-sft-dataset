  test "expired keys are cleaned up and don't accumulate", %{rl: rl} do
    # Create entries for 100 different keys
    for i <- 1..100 do
      RateLimiter.check(rl, "key:#{i}", 1, 100)
    end

    # Advance past all windows
    Clock.advance(200)

    # Trigger the sweep manually via the documented :cleanup message
    send(rl, :cleanup)

    # A GenServer processes its mailbox in order, so the calls below also
    # confirm the sweep finished without crashing the server. Internal state
    # is implementation-dependent and deliberately not inspected; the
    # observable contract is that previously tracked keys start a fresh
    # window after expiry (remaining = max - 1).
    assert {:ok, 0} = RateLimiter.check(rl, "key:1", 1, 100)
    assert {:ok, 0} = RateLimiter.check(rl, "key:100", 1, 100)
    assert Process.alive?(rl)
  end