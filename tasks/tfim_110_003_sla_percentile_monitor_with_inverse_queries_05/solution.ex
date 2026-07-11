  test "rank on an empty series is :empty" do
    start_server([])
    assert {:error, :empty} = RankPercentile.rank(:nope, 5)
  end