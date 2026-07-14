  test "the default on_flush is a no-op the aggregator can call safely" do
    agg = start_supervised!({WeightedAggregator, [max_bytes: 5, interval_ms: 5_000]})
    ref = Process.monitor(agg)

    # 11 bytes >= 5 -> a weight-triggered flush through the default callback.
    WeightedAggregator.push(agg, "hello world")

    # The default callback must not take the aggregator down: it survives the
    # flush and keeps accepting further pushes.
    refute_receive {:DOWN, ^ref, :process, ^agg, _}, 200

    WeightedAggregator.push(agg, "another oversized event")
    refute_receive {:DOWN, ^ref, :process, ^agg, _}, 200

    assert Process.alive?(agg)
  end