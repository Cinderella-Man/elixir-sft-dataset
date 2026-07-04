  test "fill: :forward carries the last known value into empty buckets" do
    result = TimeSeriesResampler.resample(@data, @interval, agg: :last, fill: :forward)

    bucket_map = Map.new(result)
    # Bucket at 2000 has last=15, so 4000 and 6000 should carry 15 forward
    assert bucket_map[4_000] == 15
    assert bucket_map[6_000] == 15
    # The filled bucket at 8000 still has the real data
    assert bucket_map[8_000] == 99
  end