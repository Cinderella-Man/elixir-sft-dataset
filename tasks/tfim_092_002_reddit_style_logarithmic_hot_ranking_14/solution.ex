  test "fully-equal items preserve original input order (stable)" do
    x = item(id: :x, upvotes: 7, created_at: @epoch)
    y = item(id: :y, upvotes: 7, created_at: @epoch)
    z = item(id: :z, upvotes: 7, created_at: @epoch)

    assert ids(Ranking.rank([x, y, z], opts())) == [:x, :y, :z]
    assert ids(Ranking.rank([z, x, y], opts())) == [:z, :x, :y]
  end