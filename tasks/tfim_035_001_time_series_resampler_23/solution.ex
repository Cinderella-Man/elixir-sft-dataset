  test "omitting :fill defaults to nil-filling empty buckets" do
    data = [{0, 10}, {4_100, 30}]
    result = TimeSeriesResampler.resample(data, 2_000, [])

    assert result == [{0, 10}, {2_000, nil}, {4_000, 30}]
  end