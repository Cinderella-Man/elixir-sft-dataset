  test "on_flush defaults to a no-op so the aggregator survives flushes without it" do
    # No :on_flush given at all: flushing must not crash the process.
    agg = start_supervised!({Aggregator, [batch_size: 2, interval_ms: 100]})
    ref = Process.monitor(agg)

    # Force a size-triggered flush, then a time-triggered flush of a leftover.
    Aggregator.push(agg, :a)
    Aggregator.push(agg, :b)
    Aggregator.push(agg, :c)

    refute_receive {:DOWN, ^ref, :process, ^agg, _reason}, 500
    assert Process.alive?(agg)
  end