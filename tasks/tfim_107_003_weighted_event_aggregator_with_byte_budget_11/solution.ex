  test "the default on_flush is a no-op the aggregator can call safely" do
    agg = start_supervised!({WeightedAggregator, [max_bytes: 5, interval_ms: 5_000]})

    # 11 bytes >= 5 -> a weight-triggered flush through the default callback.
    WeightedAggregator.push(agg, "hello world")

    # Synchronize behind the cast: this call only returns once the server has
    # processed the push (and its flush through the default callback) without
    # crashing.
    _ = :sys.get_state(agg)
    assert Process.alive?(agg)
  end