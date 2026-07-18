  test "increment refuses amounts that are not non-negative integers", %{clock: clock} do
    set_time(clock, 0)

    assert_raise FunctionClauseError, fn -> Metrics.increment(:guarded, -1) end
    assert_raise FunctionClauseError, fn -> Metrics.increment(:guarded, 1.0) end

    assert Metrics.count(:guarded) == 0
    assert Metrics.rate(:guarded, 1000) == 0
  end