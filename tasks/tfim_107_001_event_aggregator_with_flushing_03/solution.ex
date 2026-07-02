  test "batch_size of 1 flushes every event immediately" do
    agg = start_agg(batch_size: 1, interval_ms: 5_000)

    Aggregator.push(agg, :x)
    assert_receive {:flushed, [:x]}, 500

    Aggregator.push(agg, :y)
    assert_receive {:flushed, [:y]}, 500
  end