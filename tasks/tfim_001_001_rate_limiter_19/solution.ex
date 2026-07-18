  test "cleanup keeps a key that still has an active timestamp", %{rl: rl} do
    assert {:ok, 1} = RateLimiter.check(rl, "k", 2, 1_000)
    Clock.advance(600)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 2, 1_000)

    # Time 1100: the time-0 entry falls out, the time-600 entry stays active.
    Clock.advance(500)
    send(rl, :cleanup)

    # The retained (pruned) list still holds the time-600 entry, so a limit of 1
    # must be denied — a wrongly dropped key would return {:ok, 0} here.
    assert {:error, :rate_limited, 500} = RateLimiter.check(rl, "k", 1, 1_000)
  end