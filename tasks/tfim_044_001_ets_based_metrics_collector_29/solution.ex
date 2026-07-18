  test "a negative increment amount raises rather than returning :ok" do
    Metrics.increment(:strict_down, 6)

    assert_raise FunctionClauseError, fn -> Metrics.increment(:strict_down, -1) end

    assert Metrics.get(:strict_down) == 6
  end