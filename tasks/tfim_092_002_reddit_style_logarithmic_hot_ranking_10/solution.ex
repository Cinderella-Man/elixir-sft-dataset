  test "more net votes ranks above fewer given equal age" do
    high = item(id: :high, upvotes: 100, created_at: @epoch)
    low = item(id: :low, upvotes: 2, created_at: @epoch)
    assert Ranking.score(high, opts()) > Ranking.score(low, opts())
  end