  test "output is sorted ascending by bucket start" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :last, fill: nil)
    buckets = Enum.map(result, fn {b, _} -> b end)
    assert buckets == Enum.sort(buckets)
  end