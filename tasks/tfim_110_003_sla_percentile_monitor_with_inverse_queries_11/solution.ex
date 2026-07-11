  test "series are independent" do
    start_server([])
    for v <- 1..100, do: RankPercentile.record(:a, v)
    for v <- 200..209, do: RankPercentile.record(:b, v)

    assert {:ok, 0.5} = RankPercentile.rank(:a, 50)
    assert {:ok, +0.0} = RankPercentile.rank(:b, 100)
    assert {:ok, 10} = RankPercentile.count_above(:b, 100)
  end