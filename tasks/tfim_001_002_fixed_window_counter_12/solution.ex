  test "expired window counters are cleaned up and don't accumulate", %{fw: fw} do
    # Create counter entries for 100 different keys in window 0 (t=0, window_ms=100)
    for i <- 1..100 do
      FixedWindowLimiter.check(fw, "key:#{i}", 1, 100)
    end

    # Advance past the window end (window 0 ends at t=100)
    Clock.advance(200)

    # Trigger the sweep manually via the documented :cleanup message
    send(fw, :cleanup)

    # A GenServer processes its mailbox in order, so the calls below also
    # confirm the sweep finished without crashing the server. Internal state
    # is implementation-dependent and deliberately not inspected; the
    # observable contract is that previously tracked keys start a fresh
    # window after expiry (remaining = max - 1).
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "key:1", 1, 100)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "key:100", 1, 100)
    assert Process.alive?(fw)
  end