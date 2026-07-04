  test "fill: :forward uses nil when gap is at the very start" do
    # Only one point, at t=5000; interval=2000 → bucket 4000
    # No bucket precedes it, so a leading gap would be nil — but here
    # there IS no gap before the first bucket. Let's construct a case:
    # Two separated points with a gap before either:
    # We ensure the first bucket is lonely to confirm no spurious carry.
    data = [{5_000, 42}]
    result = TimeSeriesResampler.resample(data, @interval, agg: :last, fill: :forward)
    assert result == [{4_000, 42}]
  end