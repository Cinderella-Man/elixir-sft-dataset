  test "check/4 guards reject non-positive limits but accept 1", %{rl: rl} do
    assert_raise FunctionClauseError, fn ->
      RateLimiter.check(rl, "k", 0, 1_000)
    end

    assert_raise FunctionClauseError, fn ->
      RateLimiter.check(rl, "k", 1, 0)
    end

    # 1 is a positive integer and must be inside the contract for both args.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1)
    assert Process.alive?(rl)
  end