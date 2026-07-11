  test "starts a fresh batch after each flush" do
    agg = start_agg(idle_ms: 150, max_wait_ms: 5_000, batch_size: 3)

    # A size flush first.
    DebounceAggregator.push(agg, :a)
    DebounceAggregator.push(agg, :b)
    DebounceAggregator.push(agg, :c)
    assert_receive {:flushed, [:a, :b, :c]}, 500

    # A leftover single event must flush on the idle timer of a fresh batch.
    DebounceAggregator.push(agg, :d)
    assert_receive {:flushed, [:d]}, 500

    # And it keeps working afterwards.
    DebounceAggregator.push(agg, :e)
    assert_receive {:flushed, [:e]}, 500
  end