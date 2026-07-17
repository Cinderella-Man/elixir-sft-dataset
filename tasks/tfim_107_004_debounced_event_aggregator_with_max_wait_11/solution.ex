  test "default on_flush is a no-op that does not crash the aggregator" do
    agg = start_supervised!({DebounceAggregator, [idle_ms: 80, max_wait_ms: 200]})
    ref = Process.monitor(agg)

    DebounceAggregator.push(agg, :a)
    DebounceAggregator.push(agg, :b)

    # The default flush callback must swallow the batch without dying.
    refute_receive {:DOWN, ^ref, :process, _, _}, 400
    assert Process.alive?(agg)

    # And the aggregator keeps accepting work after the no-op flush.
    assert DebounceAggregator.push(agg, :c) == :ok
    refute_receive {:DOWN, ^ref, :process, _, _}, 300
  end