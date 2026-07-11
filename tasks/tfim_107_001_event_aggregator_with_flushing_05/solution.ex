  test "flushes buffered events after the interval when below batch size" do
    agg = start_agg(batch_size: 5, interval_ms: 200)

    Aggregator.push(agg, :a)
    Aggregator.push(agg, :b)

    # Below batch size, so nothing should flush right away.
    refute_receive {:flushed, _}, 80

    # Eventually the interval elapses and the partial batch is flushed.
    assert_receive {:flushed, [:a, :b]}, 500
  end