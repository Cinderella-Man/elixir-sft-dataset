  test "flushes each key's partial batch on its own interval" do
    agg = start_agg(batch_size: 5, interval_ms: 200)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :b, 2)

    refute_receive {:flushed, _, _}, 80

    assert_receive {:flushed, :a, [1]}, 500
    assert_receive {:flushed, :b, [2]}, 500
  end