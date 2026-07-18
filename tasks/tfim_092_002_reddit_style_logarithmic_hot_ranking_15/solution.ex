  test "rank handles the empty list" do
    assert Ranking.rank([], opts()) == []
  end