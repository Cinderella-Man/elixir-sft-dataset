  test "an unexpected message leaves tracking state untouched", %{rl: rl} do
    assert {:ok, 1} = RateLimiter.check(rl, "k", 2, 1_000)

    send(rl, :some_unexpected_message)
    send(rl, {:weird, :tuple, 123})

    # State unaltered: the earlier request still counts toward the limit.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 2, 1_000)
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "k", 2, 1_000)
    assert Process.alive?(rl)
  end