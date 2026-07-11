  test "max_samples bounds retained samples, dropping oldest" do
    start_server(max_samples: 5)
    for v <- 1..10, do: DecayPercentile.record(:c, v)

    # only [6,7,8,9,10] remain; all recorded at t=0 => equal weights
    assert {:ok, 6} = DecayPercentile.query(:c, 0.0)
    assert {:ok, 10} = DecayPercentile.query(:c, 1.0)
    assert {:ok, w} = DecayPercentile.total_weight(:c)
    assert_in_delta w, 5.0, 1.0e-9
  end