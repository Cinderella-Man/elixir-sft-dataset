  test "slices outside the window are excluded" do
    start_server([])

    for v <- 1..100, do: HistogramPercentile.record(:t, v)

    Clock.advance(999)
    assert {:ok, _} = HistogramPercentile.query(:t, 0.5)

    Clock.advance(1)
    assert {:error, :empty} = HistogramPercentile.query(:t, 0.5)
  end