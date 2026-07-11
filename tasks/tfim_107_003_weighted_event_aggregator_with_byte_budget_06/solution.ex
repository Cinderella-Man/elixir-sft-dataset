  test "flushes a below-budget partial batch after the interval" do
    agg = start_agg(max_bytes: 100, interval_ms: 200, size_fn: fn n -> n end)

    WeightedAggregator.push(agg, 5)
    WeightedAggregator.push(agg, 3)

    refute_receive {:flushed, _}, 80
    assert_receive {:flushed, [5, 3]}, 500
  end