  test "defaults :on_flush to a no-op two-arity callback that keeps the server alive" do
    # Started with no :on_flush at all: the default callback must accept the
    # (key, batch) pair and simply do nothing, so a flush cannot crash the
    # aggregator.
    agg = start_supervised!({KeyedAggregator, [batch_size: 1, interval_ms: 100]})
    ref = Process.monitor(agg)

    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, {:tuple, "key"}, %{payload: :two})

    refute_receive {:DOWN, ^ref, :process, _pid, _reason}, 500
    assert Process.alive?(agg)
  end