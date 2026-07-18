  test "rank handles a single item" do
    only = item(id: :only, upvotes: 3)
    assert Ranking.rank([only], now: @now) == [only]
  end