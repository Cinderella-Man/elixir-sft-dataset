  test "accumulated weight resets to zero after a flush" do
    agg = start_agg(max_bytes: 10, interval_ms: 5_000, size_fn: fn n -> n end)

    WeightedAggregator.push(agg, 6)
    WeightedAggregator.push(agg, 6)
    assert_receive {:flushed, [6, 6]}, 500

    WeightedAggregator.push(agg, 3)
    refute_receive {:flushed, _}, 100

    WeightedAggregator.push(agg, 8)
    assert_receive {:flushed, [3, 8]}, 500
  end