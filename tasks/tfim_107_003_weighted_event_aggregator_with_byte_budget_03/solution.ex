  test "a single oversized event flushes immediately" do
    agg = start_agg(max_bytes: 10, interval_ms: 5_000, size_fn: fn n -> n end)

    WeightedAggregator.push(agg, 50)
    assert_receive {:flushed, [50]}, 500
  end