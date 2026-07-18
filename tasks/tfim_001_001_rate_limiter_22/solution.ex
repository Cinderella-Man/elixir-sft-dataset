  test "keys are compared by value across term types", %{rl: rl} do
    # A tuple key and an equal tuple share one bucket (compared by value).
    assert {:ok, 1} = RateLimiter.check(rl, {:user, 1}, 2, 1_000)
    assert {:ok, 0} = RateLimiter.check(rl, {:user, 1}, 2, 1_000)
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, {:user, 1}, 2, 1_000)

    # An integer key and an atom key are independent from the tuple and each other.
    assert {:ok, 1} = RateLimiter.check(rl, 42, 2, 1_000)
    assert {:ok, 1} = RateLimiter.check(rl, :admin, 2, 1_000)

    # A different-valued tuple is its own bucket, unaffected by the exhausted one.
    assert {:ok, 1} = RateLimiter.check(rl, {:user, 2}, 2, 1_000)
  end