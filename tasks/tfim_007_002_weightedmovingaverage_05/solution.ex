  test "WMA cold-start (fewer values than period) uses adjusted weights", %{wma: s} do
    for v <- [10, 20, 30], do: WeightedMovingAverage.push(s, "a", v)

    # Only 3 of the requested 5 values are available.
    # Newest-first: [30, 20, 10], weights [3, 2, 1], denominator 6
    # WMA = (3*30 + 2*20 + 1*10) / 6 = 140 / 6
    expected = 140 / 6
    {:ok, result} = WeightedMovingAverage.get(s, "a", :wma, 5)
    assert close_to(result, expected)
  end