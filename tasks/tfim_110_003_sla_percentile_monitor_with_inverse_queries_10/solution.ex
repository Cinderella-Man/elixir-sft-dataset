  test "reset clears a series" do
    start_server([])
    for v <- 1..10, do: RankPercentile.record(:r, v)
    assert :ok = RankPercentile.reset(:r)
    assert {:error, :empty} = RankPercentile.query(:r, 0.5)
    assert {:ok, 0} = RankPercentile.count_above(:r, 0)
  end