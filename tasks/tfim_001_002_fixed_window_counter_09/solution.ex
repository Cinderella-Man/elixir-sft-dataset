  test "max_requests of 1 allows exactly one call per window", %{fw: fw} do
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 1, 500)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 1, 500)

    # Next window starts at t=500
    Clock.set(500)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 1, 500)
  end