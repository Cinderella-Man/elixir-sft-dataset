  test "bucket boundary: point exactly on boundary belongs to new bucket" do
    # t=2000 is the start of bucket [2000, 4000), not [0, 2000)
    data = [{0, 1}, {2_000, 2}]
    result = TimeSeriesResampler.resample(data, @interval, agg: :count, fill: nil)
    bucket_map = Map.new(result)
    assert bucket_map[0] == 1
    assert bucket_map[2_000] == 1
  end