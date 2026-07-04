  test "requests mid-window don't reset the counter", %{fw: fw} do
    # t=0: first request
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # t=400: second request (still in window 0)
    Clock.advance(400)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # t=800: third request (still in window 0)
    Clock.advance(400)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # t=800: fourth request — rejected, counter at 3
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # t=999: still in window 0, still rejected
    Clock.set(999)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
  end