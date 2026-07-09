  test "with equal fresh weights, percentiles match plain nearest-rank" do
    start_server([])
    for v <- 1..100, do: assert(:ok = DecayPercentile.record(:d, v))

    assert {:ok, 50} = DecayPercentile.query(:d, 0.50)
    assert {:ok, 95} = DecayPercentile.query(:d, 0.95)
    assert {:ok, 1} = DecayPercentile.query(:d, 0.0)
    assert {:ok, 100} = DecayPercentile.query(:d, 1.0)
  end