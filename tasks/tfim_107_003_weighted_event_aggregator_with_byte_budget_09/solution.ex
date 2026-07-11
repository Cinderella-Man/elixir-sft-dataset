  test "one under the budget stays buffered; exactly the budget flushes" do
    agg = start_agg(max_bytes: 10, interval_ms: 5_000, size_fn: fn n -> n end)

    # Total weight 9 = max_bytes - 1: strictly below the budget, no flush.
    WeightedAggregator.push(agg, 9)
    refute_receive {:flushed, _}, 100

    # 9 + 1 = 10 >= 10 -> flush exactly at the budget.
    WeightedAggregator.push(agg, 1)
    assert_receive {:flushed, [9, 1]}, 500
  end