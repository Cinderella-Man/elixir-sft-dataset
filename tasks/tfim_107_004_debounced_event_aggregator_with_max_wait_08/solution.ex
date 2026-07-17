  test "a batch that follows a max-wait flush gets a fresh max-wait timer" do
    agg = start_agg(idle_ms: 400, max_wait_ms: 250, batch_size: 1_000_000)

    # First batch ends on its max-wait cap (250 < idle 400).
    DebounceAggregator.push(agg, :a)
    assert_receive {:flushed, [:a]}, 600

    # Second batch: push faster than idle_ms so the idle timer can never fire.
    # Only a freshly armed max-wait timer can end this batch.
    DebounceAggregator.push(agg, :b)
    Process.sleep(100)
    DebounceAggregator.push(agg, :c)
    Process.sleep(100)
    DebounceAggregator.push(agg, :d)

    assert_receive {:flushed, [:b, :c, :d]}, 500
  end