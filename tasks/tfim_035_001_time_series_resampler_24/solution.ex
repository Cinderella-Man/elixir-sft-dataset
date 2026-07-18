  test ":mean yields a float even when all bucket values are integers" do
    data = [{0, 10}, {1_500, 20}]
    [{0, mean}] = TimeSeriesResampler.resample(data, 2_000, agg: :mean, fill: nil)

    assert is_float(mean)
    assert mean == 15.0
  end