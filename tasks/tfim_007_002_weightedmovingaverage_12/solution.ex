  test "HMA bootstrap uses full retained history", %{wma: s} do
    # Push many values with no prior gets — buffer is full history.
    for v <- 1..20, do: WeightedMovingAverage.push(s, "a", v)

    # First HMA request bootstraps from all 20 values.
    {:ok, result} = WeightedMovingAverage.get(s, "a", :hma, 4)

    # Now compare to a fresh server that does the same via only WMA requests
    # (which do not register HMA accumulators).  Both must match.
    {:ok, fresh} = WeightedMovingAverage.start_link([])
    for v <- 1..20, do: WeightedMovingAverage.push(fresh, "b", v)
    {:ok, result_b} = WeightedMovingAverage.get(fresh, "b", :hma, 4)

    assert close_to(result, result_b)
  end