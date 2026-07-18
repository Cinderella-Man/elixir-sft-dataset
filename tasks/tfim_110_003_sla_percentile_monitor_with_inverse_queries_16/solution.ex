  test "duplicate sample values each count toward the empirical CDF" do
    start_server([])
    for v <- [5, 5, 5, 10], do: RankPercentile.record(:dup, v)

    assert {:ok, 0.75} = RankPercentile.rank(:dup, 5)
    assert {:ok, +0.0} = RankPercentile.rank(:dup, 4)
    assert {:ok, 1.0} = RankPercentile.rank(:dup, 10)
    assert {:ok, 5} = RankPercentile.query(:dup, 0.5)
    assert {:ok, 1} = RankPercentile.count_above(:dup, 5)
  end