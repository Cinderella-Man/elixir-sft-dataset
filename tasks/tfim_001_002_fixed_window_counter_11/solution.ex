  test "interleaved operations on multiple keys", %{fw: fw} do
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "x", 2, 1_000)
    assert {:ok, 4} = FixedWindowLimiter.check(fw, "y", 5, 2_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "x", 2, 1_000)
    assert {:ok, 3} = FixedWindowLimiter.check(fw, "y", 5, 2_000)

    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "x", 2, 1_000)
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "y", 5, 2_000)
  end