  test "single data point produces exactly one bucket" do
    result = TimeSeriesResampler.resample([{7_500, 77}], @interval, agg: :sum, fill: nil)
    assert length(result) == 1
    [{bucket, value}] = result
    # floor(7500 / 2000) * 2000
    assert bucket == 6_000
    assert value == 77
  end