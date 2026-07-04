  test "boundary burst is allowed (known property of fixed windows)", %{fw: fw} do
    # Fill window 0 at t=999 — the very end of the window
    Clock.set(999)
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # Jump 1ms forward into window 1 — fresh counter, full allowance
    Clock.set(1_000)
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # 6 requests within 1ms of wall-clock time — the well-known
    # fixed-window-boundary burst. This is accepted by this implementation.
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
  end