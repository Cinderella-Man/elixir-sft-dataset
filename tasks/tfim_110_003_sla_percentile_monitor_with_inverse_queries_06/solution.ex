  test "count_above counts samples strictly greater than the threshold" do
    start_server([])
    for v <- 1..100, do: RankPercentile.record(:d, v)

    assert {:ok, 5} = RankPercentile.count_above(:d, 95)
    assert {:ok, 100} = RankPercentile.count_above(:d, 0)
    assert {:ok, 0} = RankPercentile.count_above(:d, 100)
  end