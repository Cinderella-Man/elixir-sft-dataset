  test "allows requests up to the limit within a window", %{fw: fw} do
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "user:1", 3, 1_000)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "user:1", 3, 1_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "user:1", 3, 1_000)
  end