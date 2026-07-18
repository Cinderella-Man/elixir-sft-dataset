  test "cleanup prunes using the most recently seen window for a key", %{rl: rl} do
    # First seen with a narrow 500ms window at time 0.
    assert {:ok, 1} = RateLimiter.check(rl, "k", 2, 500)

    # Re-seen with a much wider 5000ms window at time 100; stored window becomes 5000.
    Clock.advance(100)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 2, 5_000)

    # At time 1000 a sweep must prune with the last-seen 5000ms window, keeping both
    # entries. Using the stale 500ms window would drop the key entirely.
    Clock.advance(900)
    send(rl, :cleanup)

    # Both time-0 and time-100 entries are still active under 5000ms, so a limit of
    # 2 is now exhausted; retry_after is oldest(0) + 5000 - 1000 = 4000.
    assert {:error, :rate_limited, 4_000} = RateLimiter.check(rl, "k", 2, 5_000)
  end