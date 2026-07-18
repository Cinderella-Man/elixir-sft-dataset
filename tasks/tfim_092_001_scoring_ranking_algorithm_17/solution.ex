  test "rank handles the empty list" do
    assert Ranking.rank([], now: @now) == []
  end