  test "forward percentile query matches nearest-rank" do
    start_server([])
    for v <- 1..100, do: assert :ok = RankPercentile.record(:d, v)

    assert {:ok, 50} = RankPercentile.query(:d, 0.50)
    assert {:ok, 95} = RankPercentile.query(:d, 0.95)
    assert {:ok, 1} = RankPercentile.query(:d, 0.0)
    assert {:ok, 100} = RankPercentile.query(:d, 1.0)
  end