  test "identical items preserve original input order (stable)" do
    x = item(id: :x, upvotes: 7, downvotes: 1)
    y = item(id: :y, upvotes: 7, downvotes: 1)
    z = item(id: :z, upvotes: 7, downvotes: 1)

    assert ids(Ranking.rank([x, y, z])) == [:x, :y, :z]
    assert ids(Ranking.rank([z, x, y])) == [:z, :x, :y]
  end