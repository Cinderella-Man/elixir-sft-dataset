  test "count-based window keeps only the most recent samples" do
    start_server(max_samples: 5)

    for v <- 1..10, do: Percentile.record(:c, v)

    # only [6,7,8,9,10] remain
    assert {:ok, 6} = Percentile.query(:c, 0.0)
    assert {:ok, 10} = Percentile.query(:c, 1.0)
    # ceil(0.5*5) = 3 -> s_3 = 8
    assert {:ok, 8} = Percentile.query(:c, 0.50)
  end