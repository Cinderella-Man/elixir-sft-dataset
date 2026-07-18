  test "rank handles a single item" do
    only = item(id: :only, rating: 8.0, vote_count: 42)
    assert Ranking.rank([only]) == [only]
  end