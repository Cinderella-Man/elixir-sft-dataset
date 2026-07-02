  test "values are clamped into the edge buckets" do
    start_server([])

    HistogramPercentile.record(:c, -5)
    HistogramPercentile.record(:c, 200)

    assert {:ok, +0.0} = HistogramPercentile.query(:c, 0.0)
    assert {:ok, 100.0} = HistogramPercentile.query(:c, 1.0)
  end