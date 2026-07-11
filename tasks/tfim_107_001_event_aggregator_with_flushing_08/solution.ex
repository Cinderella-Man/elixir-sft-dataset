  test "the interval timer resets after a size-triggered flush" do
    # interval 400ms, batch size 3.
    agg = start_agg(batch_size: 3, interval_ms: 400)

    # t ~= 0: buffer one event.
    Aggregator.push(agg, :a)

    # Wait ~200ms (half the interval), then complete the batch to force a
    # size-triggered flush at t ~= 200ms.
    Process.sleep(200)
    Aggregator.push(agg, :b)
    Aggregator.push(agg, :c)
    assert_receive {:flushed, [:a, :b, :c]}, 300

    # Immediately push a new event (t ~= 200ms).
    Aggregator.push(agg, :d)

    # If the timer had NOT been reset, a stale timer from start would fire at
    # t ~= 400ms and flush [:d]. Assert that does NOT happen within the next
    # ~300ms (up to t ~= 500ms).
    refute_receive {:flushed, _}, 300

    # With a correct reset, the flush for [:d] happens ~400ms after the flush
    # at t ~= 200ms, i.e. around t ~= 600ms.
    assert_receive {:flushed, [:d]}, 400
  end