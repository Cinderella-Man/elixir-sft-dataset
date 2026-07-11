  test "series are independent" do
    start_server([])

    for v <- 1..100, do: HistogramPercentile.record(:a, v)
    for _ <- 1..10, do: HistogramPercentile.record(:b, 5)

    assert {:ok, pa} = HistogramPercentile.query(:a, 0.5)
    assert_in_delta pa, 51.0, 0.001

    HistogramPercentile.reset(:a)
    assert {:error, :empty} = HistogramPercentile.query(:a, 0.5)
    assert {:ok, _} = HistogramPercentile.query(:b, 0.5)
  end