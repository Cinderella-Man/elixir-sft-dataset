  test "cleanup reclaims an expired entry before a wider-window check", %{rl: rl} do
    # Record a request at time 0 under a 1000ms window (stored window = 1000).
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1_000)

    Clock.advance(1_500)

    # A cleanup pass prunes using the key's last-seen 1000ms window. At time 1500
    # the time-0 entry is not active for that window (0 > 1500 - 1000 is false),
    # so the key's active list becomes empty and the key is removed entirely —
    # exactly the memory-reclamation the cleanup contract mandates.
    send(rl, :cleanup)

    # The reclaimed key now behaves exactly like a never-seen key: even a wider
    # 2000ms window starts a fresh window rather than resurrecting the pruned
    # entry, so the first call must be allowed with remaining = max - 1.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 2_000)
  end