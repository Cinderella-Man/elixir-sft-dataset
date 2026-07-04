  test "larger period grows max_period and retains more history", %{wma: s} do
    for v <- 1..5, do: WeightedMovingAverage.push(s, "a", v)

    _ = WeightedMovingAverage.get(s, "a", :wma, 3)
    state1 = :sys.get_state(s)
    assert state1.streams["a"].max_period == 3

    # Requesting a larger period grows max_period but should not truncate.
    _ = WeightedMovingAverage.get(s, "a", :wma, 10)
    state2 = :sys.get_state(s)
    assert state2.streams["a"].max_period == 10
  end