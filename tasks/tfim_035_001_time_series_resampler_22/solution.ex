  test "omitting :agg defaults to :last" do
    data = [{0, 10}, {1_500, 20}]
    result = TimeSeriesResampler.resample(data, 2_000, [])

    assert result == [{0, 20}]
  end