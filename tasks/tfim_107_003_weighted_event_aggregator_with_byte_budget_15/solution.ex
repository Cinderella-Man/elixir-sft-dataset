  test "push returns :ok for both a buffering and a flushing event" do
    agg = start_agg(max_bytes: 10, interval_ms: 5_000, size_fn: fn n -> n end)

    # Buffering-only push.
    assert :ok = WeightedAggregator.push(agg, 3)
    refute_receive {:flushed, _}, 80

    # Push that triggers a flush must also just return :ok.
    assert :ok = WeightedAggregator.push(agg, 7)
    assert_receive {:flushed, [3, 7]}, 500
  end