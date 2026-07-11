  test "count_above on an empty series returns zero" do
    start_server([])
    assert {:ok, 0} = RankPercentile.count_above(:nope, 5)
  end