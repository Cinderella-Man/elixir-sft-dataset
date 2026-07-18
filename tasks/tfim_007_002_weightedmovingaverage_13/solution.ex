  test "different stream names are independent", %{wma: s} do
    for v <- 1..5, do: WeightedMovingAverage.push(s, "a", v)

    {:ok, a_wma} = WeightedMovingAverage.get(s, "a", :wma, 3)
    assert {:error, :no_data} = WeightedMovingAverage.get(s, "b", :wma, 3)

    for v <- 100..104, do: WeightedMovingAverage.push(s, "b", v)
    {:ok, b_wma} = WeightedMovingAverage.get(s, "b", :wma, 3)

    refute close_to(a_wma, b_wma)

    # "a" unaffected by pushes to "b"
    {:ok, a_wma_again} = WeightedMovingAverage.get(s, "a", :wma, 3)
    assert close_to(a_wma, a_wma_again)
  end