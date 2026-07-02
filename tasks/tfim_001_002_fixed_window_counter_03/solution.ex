  test "rejects requests past the limit within a window", %{fw: fw} do
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "k", 3, 1_000)

    assert {:error, :rate_limited, retry_after} =
             FixedWindowLimiter.check(fw, "k", 3, 1_000)

    assert is_integer(retry_after)
    assert retry_after > 0
    assert retry_after <= 1_000
  end