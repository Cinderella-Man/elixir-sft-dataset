  test "flushing one key does not reset another key's timer" do
    agg = start_agg(batch_size: 2, interval_ms: 250)

    # :b starts its interval timer at t ~= 0.
    KeyedAggregator.push(agg, :b, 100)

    # Halfway through :b's interval, force a size flush of :a.
    Process.sleep(150)
    KeyedAggregator.push(agg, :a, 1)
    KeyedAggregator.push(agg, :a, 2)
    assert_receive {:flushed, :a, [1, 2]}, 300

    # :b must still flush on its ORIGINAL schedule (~250ms from t=0), not be
    # reset by :a's flush.
    assert_receive {:flushed, :b, [100]}, 300
  end