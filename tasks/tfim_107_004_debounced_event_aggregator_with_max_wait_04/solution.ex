  test "max_wait bounds latency even while pushes keep arriving" do
    agg = start_agg(idle_ms: 500, max_wait_ms: 300, batch_size: 1_000_000)

    # Push steadily at intervals shorter than idle_ms, so the idle timer keeps
    # resetting and can never fire — only max_wait can end the batch.
    DebounceAggregator.push(agg, :a)
    Process.sleep(120)
    DebounceAggregator.push(agg, :b)
    Process.sleep(120)
    DebounceAggregator.push(agg, :c)

    # max_wait started at :a (~t0) and fires ~t300 with everything buffered.
    assert_receive {:flushed, [:a, :b, :c]}, 400
  end