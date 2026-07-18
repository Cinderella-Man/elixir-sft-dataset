  test "batch_size of one flushes every event as its own batch" do
    agg = start_agg(idle_ms: 5_000, max_wait_ms: 5_000, batch_size: 1)

    DebounceAggregator.push(agg, :a)
    DebounceAggregator.push(agg, :b)

    assert_receive {:flushed, [:a]}, 500
    assert_receive {:flushed, [:b]}, 500
  end