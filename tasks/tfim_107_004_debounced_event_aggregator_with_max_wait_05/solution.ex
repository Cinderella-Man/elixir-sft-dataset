  test "flushes immediately when the buffer reaches batch_size" do
    agg = start_agg(idle_ms: 5_000, max_wait_ms: 5_000, batch_size: 3)

    DebounceAggregator.push(agg, :a)
    DebounceAggregator.push(agg, :b)
    DebounceAggregator.push(agg, :c)

    assert_receive {:flushed, [:a, :b, :c]}, 500
  end