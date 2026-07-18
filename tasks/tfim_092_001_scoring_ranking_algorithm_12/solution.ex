  test "rank sorts items by score descending" do
    a = item(id: :a, upvotes: 100, created_at: @now)
    b = item(id: :b, upvotes: 100, created_at: @now - 100 * @hour)
    c = item(id: :c, upvotes: 2, created_at: @now)
    d = item(id: :d, upvotes: 0, downvotes: 50, created_at: @now)

    ranked = Ranking.rank([c, d, a, b], now: @now)
    assert ids(ranked) == [:a, :b, :c, :d]
  end