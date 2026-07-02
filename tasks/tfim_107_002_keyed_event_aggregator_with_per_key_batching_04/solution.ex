  test "keys buffer and flush independently by size" do
    agg = start_agg(batch_size: 2, interval_ms: 5_000)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :b, 10)
    KeyedAggregator.push(agg, :a, 2)

    # :a reached batch size and flushes; :b has one buffered event, no flush.
    assert_receive {:flushed, :a, [1, 2]}, 500
    refute_receive {:flushed, :b, _}, 150
  end