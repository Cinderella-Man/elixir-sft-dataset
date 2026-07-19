  test "an above-range value lands in the last bucket rather than being dropped" do
    start_server([])

    HistogramPercentile.record(:hic, 500)

    assert {:ok, p50} = HistogramPercentile.query(:hic, 0.5)
    assert_in_delta p50, 95.0, 0.001
  end