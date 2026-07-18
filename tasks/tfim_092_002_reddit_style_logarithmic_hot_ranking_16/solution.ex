  test "rank handles a single item" do
    only = item(id: :only, upvotes: 3, created_at: @epoch)
    assert Ranking.rank([only], opts()) == [only]
  end