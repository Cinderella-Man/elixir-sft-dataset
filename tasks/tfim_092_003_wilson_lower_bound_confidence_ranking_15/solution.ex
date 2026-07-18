  test "rank handles a single item" do
    only = item(id: :only, upvotes: 3, downvotes: 1)
    assert Ranking.rank([only]) == [only]
  end