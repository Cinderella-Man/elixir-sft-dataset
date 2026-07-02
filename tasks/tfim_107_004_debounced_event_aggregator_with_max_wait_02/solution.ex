  test "flushes a coalesced batch after the stream goes idle" do
    agg = start_agg(idle_ms: 150, max_wait_ms: 5_000, batch_size: 1_000_000)

    DebounceAggregator.push(agg, :a)
    DebounceAggregator.push(agg, :b)

    # Still within the idle window, nothing yet.
    refute_receive {:flushed, _}, 80

    # After the stream is quiet for idle_ms, both events flush as one batch.
    assert_receive {:flushed, [:a, :b]}, 500
  end