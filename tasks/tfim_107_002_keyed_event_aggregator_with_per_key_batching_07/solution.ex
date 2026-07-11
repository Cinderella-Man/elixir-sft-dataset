  test "keeps aggregating a key after a time-triggered partial flush" do
    agg = start_agg(batch_size: 3, interval_ms: 150)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :a, 2)
    KeyedAggregator.push(agg, :a, 3)
    assert_receive {:flushed, :a, [1, 2, 3]}, 500

    KeyedAggregator.push(agg, :a, 4)
    assert_receive {:flushed, :a, [4]}, 500

    KeyedAggregator.push(agg, :a, 5)
    assert_receive {:flushed, :a, [5]}, 500
  end