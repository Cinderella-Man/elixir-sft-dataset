  test "different keys are completely independent", %{fw: fw} do
    # Exhaust key "a"
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "a", 3, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "a", 3, 1_000)

    # Key "b" should be unaffected
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "b", 3, 1_000)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "b", 3, 1_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "b", 3, 1_000)
  end