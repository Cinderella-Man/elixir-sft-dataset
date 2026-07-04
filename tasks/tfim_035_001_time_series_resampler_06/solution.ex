  test ":mean computes the arithmetic mean for each bucket" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :mean, fill: nil)

    {_, mean_0} = Enum.find(result, fn {b, _} -> b == 0 end)
    # (10 + 20) / 2
    assert_in_delta mean_0, 15.0, 0.001

    {_, mean_2000} = Enum.find(result, fn {b, _} -> b == 2_000 end)
    # (5 + 15) / 2
    assert_in_delta mean_2000, 10.0, 0.001

    {_, mean_8000} = Enum.find(result, fn {b, _} -> b == 8_000 end)
    assert_in_delta mean_8000, 99.0, 0.001
  end