  test "rank sorts items by score descending" do
    a = item(id: :a, upvotes: 1000, created_at: @epoch)
    b = item(id: :b, upvotes: 10, created_at: @epoch)
    c = item(id: :c, upvotes: 0, downvotes: 100, created_at: @epoch)

    assert ids(Ranking.rank([c, b, a], opts())) == [:a, :b, :c]
  end