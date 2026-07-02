  test "flushes a key when it reaches the configured batch size" do
    agg = start_agg(batch_size: 3, interval_ms: 5_000)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :a, 2)
    KeyedAggregator.push(agg, :a, 3)

    assert_receive {:flushed, :a, [1, 2, 3]}, 500
  end