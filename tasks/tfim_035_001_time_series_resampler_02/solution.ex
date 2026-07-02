  test ":last picks the value with the highest timestamp in each bucket" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :last, fill: nil)

    assert {0, 20} = Enum.find(result, fn {b, _} -> b == 0 end)
    assert {2000, 15} = Enum.find(result, fn {b, _} -> b == 2_000 end)
    assert {8000, 99} = Enum.find(result, fn {b, _} -> b == 8_000 end)
  end