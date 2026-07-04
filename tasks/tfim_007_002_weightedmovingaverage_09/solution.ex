  test "HMA with insufficient values returns :insufficient_data", %{wma: s} do
    for v <- [1, 2, 3], do: WeightedMovingAverage.push(s, "a", v)

    assert {:error, :insufficient_data} = WeightedMovingAverage.get(s, "a", :hma, 4)
  end