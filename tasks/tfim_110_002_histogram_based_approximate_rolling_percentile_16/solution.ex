  test "slice width is the window divided by slots, rounded up" do
    # slice_ms = ceil(1000 / 4) = 250, so a sample at t = 250 starts slice 250.
    start_server(window_ms: 1000, slots: 4)

    Clock.advance(250)
    HistogramPercentile.record(:sw, 95)

    Clock.advance(999)
    # now = 1249: 1249 - 250 = 999 < 1000, still live.
    assert {:ok, p50} = HistogramPercentile.query(:sw, 0.5)
    assert_in_delta p50, 95.0, 0.001

    Clock.advance(1)
    # now = 1250: 1250 - 250 = 1000, aged out.
    assert {:error, :empty} = HistogramPercentile.query(:sw, 0.5)
  end