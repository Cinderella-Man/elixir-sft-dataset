  test "the interval timer resets after a weight-triggered flush" do
    agg = start_agg(max_bytes: 100, interval_ms: 400, size_fn: fn n -> n end)

    # t ~= 0: buffer weight 10.
    WeightedAggregator.push(agg, 10)

    # At t ~= 200, push a heavy event to force a weight-triggered flush.
    Process.sleep(200)
    WeightedAggregator.push(agg, 95)
    assert_receive {:flushed, [10, 95]}, 300

    # New event right after the flush (t ~= 200).
    WeightedAggregator.push(agg, 5)

    # A stale timer from start would fire at t ~= 400 and flush [5]. With a
    # correct reset it does NOT happen within the next ~300ms.
    refute_receive {:flushed, _}, 300

    # The reset timer flushes [5] ~400ms after the flush at t ~= 200.
    assert_receive {:flushed, [5]}, 400
  end