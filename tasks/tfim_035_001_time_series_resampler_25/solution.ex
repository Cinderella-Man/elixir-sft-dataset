  test "fill: :forward starts with no carried value at the earliest bucket" do
    # The grid begins at the earliest point's floored bucket, so the leftmost
    # emitted bucket is never empty and never receives a carried value: it
    # holds its own aggregate under both fill modes, and the two modes differ
    # only in the interior gap.
    data = [{-3_000, 7}, {1_000, 9}]

    forward = TimeSeriesResampler.resample(data, @interval, agg: :sum, fill: :forward)
    nil_filled = TimeSeriesResampler.resample(data, @interval, agg: :sum, fill: nil)

    assert forward == [{-4_000, 7}, {-2_000, 7}, {0, 9}]
    assert nil_filled == [{-4_000, 7}, {-2_000, nil}, {0, 9}]
    assert hd(forward) == hd(nil_filled)
  end