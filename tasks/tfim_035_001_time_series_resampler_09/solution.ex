  test "fill: :nil emits nil for empty buckets" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :last, fill: nil)

    bucket_map = Map.new(result)
    assert Map.has_key?(bucket_map, 4_000)
    assert Map.has_key?(bucket_map, 6_000)
    assert bucket_map[4_000] == nil
    assert bucket_map[6_000] == nil
  end