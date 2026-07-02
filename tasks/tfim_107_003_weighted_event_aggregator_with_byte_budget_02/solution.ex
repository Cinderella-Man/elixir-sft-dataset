  test "flushes when accumulated weight reaches the byte budget" do
    agg = start_agg(max_bytes: 10, interval_ms: 5_000, size_fn: fn n -> n end)

    WeightedAggregator.push(agg, 4)
    WeightedAggregator.push(agg, 4)

    # Total weight 8 < 10, so nothing yet.
    refute_receive {:flushed, _}, 80

    WeightedAggregator.push(agg, 3)
    # Total weight 11 >= 10 -> flush the whole buffer in push order.
    assert_receive {:flushed, [4, 4, 3]}, 500
  end