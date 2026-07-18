  test "push rejects non-numeric values", %{wma: s} do
    assert_raise FunctionClauseError, fn ->
      WeightedMovingAverage.push(s, "a", :not_a_number)
    end
  end