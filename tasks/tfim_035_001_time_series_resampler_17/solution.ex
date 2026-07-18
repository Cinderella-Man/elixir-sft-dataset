  test "input in reverse order gives same result as sorted input" do
    forward = TimeSeriesResampler.resample(@data, @interval, agg: :sum, fill: nil)
    backward = TimeSeriesResampler.resample(Enum.reverse(@data), @interval, agg: :sum, fill: nil)
    assert forward == backward
  end