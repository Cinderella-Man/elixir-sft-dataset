  test ":count with fill: :forward fills gaps with count from last non-empty bucket" do
    # Bucket 0: 2 points; bucket 2000: empty; bucket 4000: 1 point
    data = [{0, 10}, {500, 20}, {4_100, 30}]
    result = TimeSeriesResampler.resample(data, @interval, agg: :count, fill: :forward)
    bucket_map = Map.new(result)
    assert bucket_map[0] == 2
    # carried forward from bucket 0
    assert bucket_map[2_000] == 2
    assert bucket_map[4_000] == 1
  end