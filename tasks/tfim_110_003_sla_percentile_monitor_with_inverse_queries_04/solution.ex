  test "rank clamps below min and above max" do
    start_server([])
    for v <- 1..10, do: RankPercentile.record(:d, v)

    assert {:ok, +0.0} = RankPercentile.rank(:d, 0)
    assert {:ok, 1.0} = RankPercentile.rank(:d, 999)
  end