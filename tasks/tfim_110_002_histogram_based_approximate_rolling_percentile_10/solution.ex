  test "a below-range value lands in the first bucket rather than being dropped" do
    start_server([])

    HistogramPercentile.record(:lowc, -5)

    # A single sample clamped into bucket 0 -> the median sits mid-bucket.
    assert {:ok, p50} = HistogramPercentile.query(:lowc, 0.5)
    assert_in_delta p50, 5.0, 0.001
  end