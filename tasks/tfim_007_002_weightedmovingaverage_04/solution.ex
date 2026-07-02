  test "WMA with period smaller than buffer uses only the newest N", %{wma: s} do
    for v <- [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], do: WeightedMovingAverage.push(s, "a", v)

    # Newest-first: [10, 9, 8, ...]. WMA(3): (3*10 + 2*9 + 1*8) / 6 = 56 / 6
    expected = 56 / 6
    {:ok, result} = WeightedMovingAverage.get(s, "a", :wma, 3)
    assert close_to(result, expected)
  end