  test "registers under :name and accepts pushes addressed to that name" do
    start_agg(name: :promise_named_aggregator, idle_ms: 120, max_wait_ms: 5_000)

    assert is_pid(Process.whereis(:promise_named_aggregator))

    DebounceAggregator.push(:promise_named_aggregator, :a)
    DebounceAggregator.push(:promise_named_aggregator, :b)

    assert_receive {:flushed, [:a, :b]}, 500
  end