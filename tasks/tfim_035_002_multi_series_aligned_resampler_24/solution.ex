  test ":mean yields a float even when the mean is a whole number" do
    # mem's mean is exactly 12; integer division or a rounding shortcut would
    # return 12 rather than the promised float.
    series = %{cpu: [{0, 1}, {500, 2}], mem: [{0, 10}, {500, 11}, {900, 15}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :mean, fill: nil)

    m0 = row(result, 0)
    assert m0.cpu === 1.5
    assert m0.mem === 12.0
  end