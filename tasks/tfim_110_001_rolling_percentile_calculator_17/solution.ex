  test "count limit still applies when a time window is also configured" do
    start_server(window_ms: 1_000, max_samples: 3)

    # Every sample is recorded at t=0, so nothing has expired; only the count
    # window can trim, and it must leave the three most recent: [8, 9, 10].
    for v <- 1..10, do: Percentile.record(:both, v)

    assert {:ok, 8} = Percentile.query(:both, 0.0)
    assert {:ok, 10} = Percentile.query(:both, 1.0)
    # ceil(0.5*3) = 2 -> s_2 = 9
    assert {:ok, 9} = Percentile.query(:both, 0.50)
  end