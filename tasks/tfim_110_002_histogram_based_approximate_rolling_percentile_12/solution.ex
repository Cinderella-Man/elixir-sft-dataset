  test "a value exactly on an interior edge belongs to the higher bucket" do
    start_server([])

    HistogramPercentile.record(:edge, 10)

    # Bucket 1 covers [10, 20), so the estimate is mid-bucket-1.
    assert {:ok, p50} = HistogramPercentile.query(:edge, 0.5)
    assert_in_delta p50, 15.0, 0.001
  end