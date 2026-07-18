  test "all points in the same bucket produces one bucket" do
    data = [{100, 1}, {200, 2}, {300, 3}]
    result = TimeSeriesResampler.resample(data, @interval, agg: :count, fill: nil)
    assert length(result) == 1
    assert [{0, 3}] = result
  end