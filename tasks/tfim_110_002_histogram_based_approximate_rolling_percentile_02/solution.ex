  test "histogram quantile estimates are deterministic for a known distribution" do
    start_server([])

    for v <- 1..100, do: assert(:ok = HistogramPercentile.record(:d, v))

    assert {:ok, p50} = HistogramPercentile.query(:d, 0.50)
    assert_in_delta p50, 51.0, 0.001

    assert {:ok, p95} = HistogramPercentile.query(:d, 0.95)
    assert_in_delta p95, 95.4545, 0.05

    assert {:ok, +0.0} = HistogramPercentile.query(:d, 0.0)
    assert {:ok, 100.0} = HistogramPercentile.query(:d, 1.0)
  end