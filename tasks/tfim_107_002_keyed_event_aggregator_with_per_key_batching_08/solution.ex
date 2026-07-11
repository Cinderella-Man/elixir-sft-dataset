  test "a key's interval timer resets after that key's size-triggered flush" do
    agg = start_agg(batch_size: 3, interval_ms: 400)

    # t ~= 0: buffer one event under :a.
    KeyedAggregator.push(agg, :a, 1)

    # Complete the batch at t ~= 200 to force a size-triggered flush.
    Process.sleep(200)
    KeyedAggregator.push(agg, :a, 2)
    KeyedAggregator.push(agg, :a, 3)
    assert_receive {:flushed, :a, [1, 2, 3]}, 300

    # New event for :a right after the flush (t ~= 200).
    KeyedAggregator.push(agg, :a, 4)

    # A stale timer from the start would fire at t ~= 400 and flush [4]. With a
    # correct reset, that does NOT happen within the next ~300ms.
    refute_receive {:flushed, :a, _}, 300

    # The reset timer flushes [4] ~400ms after the flush at t ~= 200.
    assert_receive {:flushed, :a, [4]}, 400
  end