  test ":mean produces per-series floats" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :mean, fill: :nil)

    m0 = row(result, 0)
    assert_in_delta m0.cpu, 15.0, 0.001
    assert_in_delta m0.mem, 1.0, 0.001

    m2 = row(result, 2_000)
    assert_in_delta m2.cpu, 10.0, 0.001
    assert_in_delta m2.mem, 2.0, 0.001
  end