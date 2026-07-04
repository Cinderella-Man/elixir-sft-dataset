  test ":max returns the maximum value in each bucket" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :max, fill: nil)

    assert {0, 20} = Enum.find(result, fn {b, _} -> b == 0 end)
    assert {2000, 15} = Enum.find(result, fn {b, _} -> b == 2_000 end)
    assert {8000, 99} = Enum.find(result, fn {b, _} -> b == 8_000 end)
  end