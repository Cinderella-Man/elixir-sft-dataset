  test "a value exactly on the top edge belongs to the closed last bucket" do
    start_server([])

    HistogramPercentile.record(:top, 100)

    assert {:ok, p50} = HistogramPercentile.query(:top, 0.5)
    assert_in_delta p50, 95.0, 0.001
  end