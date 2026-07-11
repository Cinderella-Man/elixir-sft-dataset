  test "count-based window keeps only the most recent samples" do
    start_server(max_samples: 5)
    for v <- 1..10, do: RankPercentile.record(:c, v)

    # only [6,7,8,9,10] remain
    assert {:ok, 6} = RankPercentile.query(:c, 0.0)
    assert {:ok, 0.2} = RankPercentile.rank(:c, 6)
    assert {:ok, 2} = RankPercentile.count_above(:c, 8)
  end