  test "push returns :ok immediately without waiting for a flush" do
    agg = start_agg(idle_ms: 5_000, max_wait_ms: 5_000, batch_size: 1_000_000)

    assert DebounceAggregator.push(agg, :a) == :ok
    assert DebounceAggregator.push(agg, :b) == :ok

    # Neither timer has expired, so push clearly did not block on a flush.
    refute_receive {:flushed, _}, 150
  end