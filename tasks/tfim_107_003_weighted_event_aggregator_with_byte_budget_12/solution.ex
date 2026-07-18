  test "a time-triggered flush leaves an empty buffer and zero accumulated weight" do
    agg = start_agg(max_bytes: 10, interval_ms: 200, size_fn: fn n -> n end)

    # 9 < 10 stays buffered until the interval elapses.
    WeightedAggregator.push(agg, 9)
    assert_receive {:flushed, [9]}, 500

    # If the weight survived the time flush, 9 + 9 = 18 >= 10 would flush at once.
    WeightedAggregator.push(agg, 9)
    refute_receive {:flushed, _}, 100

    # A fresh buffer starting from zero: 9 + 1 = 10 >= 10 flushes exactly here.
    WeightedAggregator.push(agg, 1)
    assert_receive {:flushed, [9, 1]}, 500
  end