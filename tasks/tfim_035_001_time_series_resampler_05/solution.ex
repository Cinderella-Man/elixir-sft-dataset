  test ":count returns the number of points in each bucket" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :count, fill: nil)

    assert {0, 2} = Enum.find(result, fn {b, _} -> b == 0 end)
    assert {2000, 2} = Enum.find(result, fn {b, _} -> b == 2_000 end)
    assert {8000, 1} = Enum.find(result, fn {b, _} -> b == 8_000 end)
  end