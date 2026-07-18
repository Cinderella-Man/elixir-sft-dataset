  test "events can be pushed through a registered name" do
    start_agg(
      name: :weighted_aggregator_named_target,
      max_bytes: 10,
      interval_ms: 5_000,
      size_fn: fn n -> n end
    )

    WeightedAggregator.push(:weighted_aggregator_named_target, 4)
    refute_receive {:flushed, _}, 80

    WeightedAggregator.push(:weighted_aggregator_named_target, 6)
    assert_receive {:flushed, [4, 6]}, 500
  end