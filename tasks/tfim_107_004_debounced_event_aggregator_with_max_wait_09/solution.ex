  test "default batch_size of infinity applies no size trigger" do
    agg = start_agg(idle_ms: 150, max_wait_ms: 5_000)

    for event <- [:a, :b, :c, :d, :e], do: DebounceAggregator.push(agg, event)

    # No size flush may split the burst; the whole burst coalesces on idle.
    assert_receive {:flushed, [:a, :b, :c, :d, :e]}, 500
    refute_receive {:flushed, _}, 200
  end