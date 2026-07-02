  test "counter resets abruptly at window boundary", %{fw: fw} do
    # Fill up window 0 (t=0..999)
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # Cross into window 1 (t=1000..1999). Counter resets.
    Clock.set(1_000)
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
  end