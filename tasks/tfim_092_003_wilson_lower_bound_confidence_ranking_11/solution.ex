  test "rank sorts items by score descending" do
    a = item(id: :a, upvotes: 100, downvotes: 5)
    b = item(id: :b, upvotes: 10, downvotes: 1)
    c = item(id: :c, upvotes: 1, downvotes: 0)
    d = item(id: :d, upvotes: 2, downvotes: 20)

    assert ids(Ranking.rank([c, d, a, b])) == [:a, :b, :c, :d]
  end