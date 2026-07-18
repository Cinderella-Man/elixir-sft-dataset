  test "ignores unrelated messages without crashing or disturbing a key's buffer" do
    agg = start_agg(batch_size: 3, interval_ms: 30_000)
    mon = Process.monitor(agg)

    KeyedAggregator.push(agg, :a, 1)

    send(agg, :some_unrelated_message)
    send(agg, {:unexpected, :tuple, 42})
    send(agg, "a plain string")

    # No flush may be provoked by junk, and the process must stay up.
    refute_receive {:flushed, _, _}, 200
    refute_receive {:DOWN, ^mon, :process, _pid, _reason}, 100

    # The buffer for :a is untouched: the batch still completes in push order.
    KeyedAggregator.push(agg, :a, 2)
    KeyedAggregator.push(agg, :a, 3)
    assert_receive {:flushed, :a, [1, 2, 3]}, 1_000
  end