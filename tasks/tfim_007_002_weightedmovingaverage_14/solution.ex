  test "get with unknown type raises a FunctionClauseError", %{wma: s} do
    assert_raise FunctionClauseError, fn ->
      WeightedMovingAverage.get(s, "a", :nope, 3)
    end
  end