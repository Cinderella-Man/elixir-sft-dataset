  test "cleanup removes a key whose entries are exactly window_ms old", %{rl: rl} do
    # Entry recorded at time 0 with a 1000ms window.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1_000)

    # At exactly time 1000 the entry is not active (0 > 1000 - 1000 is false),
    # so the key's active list is empty and the key is removed entirely.
    Clock.advance(1_000)
    send(rl, :cleanup)

    # A removed key behaves exactly like a never-seen key: checked here with a
    # wider window that would still have covered the time-0 entry had it been
    # retained, the first call must be allowed with remaining = max - 1.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 2_000)
    assert Process.alive?(rl)
  end