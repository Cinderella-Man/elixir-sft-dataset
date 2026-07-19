  test "samples inside one slice accumulate into the same histogram" do
    # slice_ms = ceil(1000 / 4) = 250, so t = 0 and t = 4 share slice 0.
    start_server(window_ms: 1000, slots: 4)

    HistogramPercentile.record(:acc, 5)
    Clock.advance(4)
    HistogramPercentile.record(:acc, 95)

    # n == 2: target 1.0 exhausts bucket 0 exactly -> its high edge.
    assert {:ok, p50} = HistogramPercentile.query(:acc, 0.5)
    assert_in_delta p50, 10.0, 0.001
  end