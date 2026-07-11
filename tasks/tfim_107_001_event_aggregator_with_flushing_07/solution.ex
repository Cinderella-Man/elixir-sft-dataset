  test "keeps aggregating after a time-triggered partial flush" do
    agg = start_agg(batch_size: 3, interval_ms: 150)

    # First a size flush.
    Aggregator.push(agg, :a)
    Aggregator.push(agg, :b)
    Aggregator.push(agg, :c)
    assert_receive {:flushed, [:a, :b, :c]}, 500

    # Then a leftover single event that must flush on the timer.
    Aggregator.push(agg, :d)
    assert_receive {:flushed, [:d]}, 500

    # And it keeps working afterwards.
    Aggregator.push(agg, :e)
    assert_receive {:flushed, [:e]}, 500
  end