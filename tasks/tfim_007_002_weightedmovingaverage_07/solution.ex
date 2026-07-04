  test "WMA values buffer is bounded by max_period", %{wma: s} do
    for v <- 1..20, do: WeightedMovingAverage.push(s, "a", v)

    # Ask for period 3 — max_period becomes 3, buffer trims to 3.
    _ = WeightedMovingAverage.get(s, "a", :wma, 3)

    # Push more values; buffer should stay at 3 (the current max_period).
    for v <- 21..30, do: WeightedMovingAverage.push(s, "a", v)
    _ = WeightedMovingAverage.get(s, "a", :wma, 3)

    state = :sys.get_state(s)
    assert length(state.streams["a"].values) == 3
  end