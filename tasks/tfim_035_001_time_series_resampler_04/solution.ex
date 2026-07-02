  test ":sum adds all values in each bucket" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :sum, fill: nil)

    # 10 + 20
    assert {0, 30} = Enum.find(result, fn {b, _} -> b == 0 end)
    # 5 + 15
    assert {2000, 20} = Enum.find(result, fn {b, _} -> b == 2_000 end)
    assert {8000, 99} = Enum.find(result, fn {b, _} -> b == 8_000 end)
  end