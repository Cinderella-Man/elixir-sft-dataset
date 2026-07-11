  test "counts from multiple live slices are aggregated" do
    start_server([])

    for v <- 1..50, do: HistogramPercentile.record(:t, v)
    Clock.advance(100)
    for v <- 51..100, do: HistogramPercentile.record(:t, v)

    assert {:ok, p50} = HistogramPercentile.query(:t, 0.50)
    assert_in_delta p50, 51.0, 0.001
  end