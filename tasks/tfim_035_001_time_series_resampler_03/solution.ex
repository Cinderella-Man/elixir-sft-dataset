  test ":first picks the value with the lowest timestamp in each bucket" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :first, fill: nil)

    assert {0, 10} = Enum.find(result, fn {b, _} -> b == 0 end)
    assert {2000, 5} = Enum.find(result, fn {b, _} -> b == 2_000 end)
    assert {8000, 99} = Enum.find(result, fn {b, _} -> b == 8_000 end)
  end