  test "the accumulated weight restarts from exactly zero after a flush" do
    agg = start_agg(max_bytes: 10, interval_ms: 5_000, size_fn: fn n -> n end)

    # Oversized event -> immediate flush; buffer and weight reset.
    WeightedAggregator.push(agg, 10)
    assert_receive {:flushed, [10]}, 500

    # After the reset, 9 = max_bytes - 1 must sit strictly below the budget.
    WeightedAggregator.push(agg, 9)
    refute_receive {:flushed, _}, 100

    WeightedAggregator.push(agg, 1)
    assert_receive {:flushed, [9, 1]}, 500
  end