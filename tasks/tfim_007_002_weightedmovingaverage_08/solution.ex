  test "larger period grows max_period and retains more history", %{wma: s} do
    for v <- 1..5, do: WeightedMovingAverage.push(s, "a", v)

    # A period-3 request caps retention at 3: only [5, 4, 3] survive, so a
    # period-5 window cold-starts over those three instead of seeing [2, 1].
    # WMA = (3*5 + 2*4 + 1*3) / 6 = 26 / 6  (full history would give 55 / 15)
    _ = WeightedMovingAverage.get(s, "a", :wma, 3)
    {:ok, narrow} = WeightedMovingAverage.get(s, "a", :wma, 5)
    assert close_to(narrow, 26 / 6)
    refute close_to(narrow, 55 / 15)

    # Requesting a larger period widens retention without truncating: the next
    # ten pushes are all kept, so WMA(10) spans the full [15, 14, ..., 6]
    # window. sum(weight_i * value_i) = 660, sum(weights) = 55 → 12.0
    _ = WeightedMovingAverage.get(s, "a", :wma, 10)
    for v <- 6..15, do: WeightedMovingAverage.push(s, "a", v)

    {:ok, wide} = WeightedMovingAverage.get(s, "a", :wma, 10)
    assert close_to(wide, 660 / 55)
  end