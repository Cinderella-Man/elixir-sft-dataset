  test "batch_size of 1 flushes every event for a key immediately" do
    agg = start_agg(batch_size: 1, interval_ms: 5_000)

    KeyedAggregator.push(agg, :x, :first)
    assert_receive {:flushed, :x, [:first]}, 500

    KeyedAggregator.push(agg, :x, :second)
    assert_receive {:flushed, :x, [:second]}, 500
  end