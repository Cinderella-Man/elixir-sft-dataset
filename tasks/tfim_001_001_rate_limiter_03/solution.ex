  test "rejects the request that exceeds the limit", %{rl: rl} do
    for _ <- 1..3, do: RateLimiter.check(rl, "k", 3, 1_000)

    assert {:error, :rate_limited, retry_after} =
             RateLimiter.check(rl, "k", 3, 1_000)

    assert is_integer(retry_after)
    assert retry_after > 0
    assert retry_after <= 1_000
  end