  test "new/2 rejects a non-positive or non-integer window_ms" do
    name = :"swguard_#{:erlang.unique_integer([:positive])}"

    assert_raise FunctionClauseError, fn -> SlidingWindowLeaderboard.new(name, 0) end
    assert_raise FunctionClauseError, fn -> SlidingWindowLeaderboard.new(name, -1) end
    assert_raise FunctionClauseError, fn -> SlidingWindowLeaderboard.new(name, 100.0) end
    assert_raise FunctionClauseError, fn -> SlidingWindowLeaderboard.new("not_atom", 100) end
  end