  test "check/4 raises on non-integer limits", %{rl: rl} do
    assert_raise FunctionClauseError, fn ->
      RateLimiter.check(rl, "k", 2.0, 1_000)
    end

    assert_raise FunctionClauseError, fn ->
      RateLimiter.check(rl, "k", 2, 1_000.0)
    end

    assert Process.alive?(rl)
  end