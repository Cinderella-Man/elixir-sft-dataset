  test "empty input returns empty list" do
    assert [] = TimeSeriesResampler.resample([], @interval, agg: :last, fill: nil)
  end