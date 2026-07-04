  test "works with very large window", %{fw: fw} do
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 1, 86_400_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 1, 86_400_000)

    # Next day's window
    Clock.set(86_400_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 1, 86_400_000)
  end