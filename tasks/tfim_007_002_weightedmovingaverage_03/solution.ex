  test "WMA with full window is correctly weighted", %{wma: s} do
    for v <- [10, 20, 30, 40, 50], do: WeightedMovingAverage.push(s, "a", v)

    # Newest-first: [50, 40, 30, 20, 10]
    # WMA(period=5): (5*50 + 4*40 + 3*30 + 2*20 + 1*10) / 15
    #              = (250 + 160 + 90 + 40 + 10) / 15 = 550 / 15
    expected = 550 / 15

    {:ok, result} = WeightedMovingAverage.get(s, "a", :wma, 5)
    assert close_to(result, expected)
  end