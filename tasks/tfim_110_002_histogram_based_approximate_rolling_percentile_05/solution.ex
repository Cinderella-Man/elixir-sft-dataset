  test "reset clears a series and it can be reused" do
    start_server([])

    for v <- 1..50, do: HistogramPercentile.record(:r, v)
    assert {:ok, _} = HistogramPercentile.query(:r, 0.5)

    assert :ok = HistogramPercentile.reset(:r)
    assert {:error, :empty} = HistogramPercentile.query(:r, 0.5)

    HistogramPercentile.record(:r, 55)
    assert {:ok, _} = HistogramPercentile.query(:r, 0.5)
  end