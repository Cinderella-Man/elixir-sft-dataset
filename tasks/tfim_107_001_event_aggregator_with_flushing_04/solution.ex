  test "multiple full batches flush in order with fresh buffers" do
    agg = start_agg(batch_size: 2, interval_ms: 5_000)

    Aggregator.push(agg, 1)
    Aggregator.push(agg, 2)
    Aggregator.push(agg, 3)
    Aggregator.push(agg, 4)

    assert_receive {:flushed, [1, 2]}, 500
    assert_receive {:flushed, [3, 4]}, 500
  end