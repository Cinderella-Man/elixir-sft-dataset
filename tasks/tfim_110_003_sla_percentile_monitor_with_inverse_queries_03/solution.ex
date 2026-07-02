  test "rank returns the fraction of samples at or below a value" do
    start_server([])
    for v <- 1..100, do: RankPercentile.record(:d, v)

    assert {:ok, 0.5} = RankPercentile.rank(:d, 50)
    assert {:ok, 0.01} = RankPercentile.rank(:d, 1)
    assert {:ok, 1.0} = RankPercentile.rank(:d, 100)
  end