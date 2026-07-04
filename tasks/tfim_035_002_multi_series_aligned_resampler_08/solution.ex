  test "every bucket in the joint range is present and sorted" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :last, fill: :nil)
    buckets = Enum.map(result, fn {b, _} -> b end)

    assert buckets == [0, 2_000, 4_000, 6_000, 8_000]
    assert buckets == Enum.sort(buckets)
  end