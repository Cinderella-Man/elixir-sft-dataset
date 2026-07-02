  test "get on empty stream returns :no_data", %{wma: s} do
    assert {:error, :no_data} = WeightedMovingAverage.get(s, "x", :wma, 3)
    assert {:error, :no_data} = WeightedMovingAverage.get(s, "x", :hma, 4)
  end