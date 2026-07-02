  test "unknown series returns :empty" do
    start_server([])
    assert {:error, :empty} = HistogramPercentile.query(:nope, 0.5)
  end