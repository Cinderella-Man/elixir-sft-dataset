  test "output contains every bucket between first and last, none missing" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :last, fill: nil)
    buckets = Enum.map(result, fn {b, _} -> b end)

    expected_buckets = [0, 2_000, 4_000, 6_000, 8_000]
    assert buckets == expected_buckets
  end