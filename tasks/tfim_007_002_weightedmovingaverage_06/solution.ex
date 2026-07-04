  test "single-value WMA equals that value", %{wma: s} do
    WeightedMovingAverage.push(s, "a", 42)
    {:ok, result} = WeightedMovingAverage.get(s, "a", :wma, 10)
    assert result == 42.0
  end