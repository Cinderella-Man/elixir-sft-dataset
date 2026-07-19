  test "reusing a ring slot discards the previous cycle's counts" do
    # slice_ms = 250 with 4 slots, so slice 4 (t = 1000) reuses slot 0.
    start_server(window_ms: 1000, slots: 4)

    HistogramPercentile.record(:ring, 5)
    Clock.advance(1000)
    HistogramPercentile.record(:ring, 95)

    # Only the new sample survives; if the old counts lingered the median
    # would be pulled down to bucket 0's high edge (10.0).
    assert {:ok, p50} = HistogramPercentile.query(:ring, 0.5)
    assert_in_delta p50, 95.0, 0.001
  end