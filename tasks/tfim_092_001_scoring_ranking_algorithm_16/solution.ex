  test "fully-equal items preserve original input order (stable)" do
    x = item(id: :x, upvotes: 7, created_at: @now)
    y = item(id: :y, upvotes: 7, created_at: @now)
    z = item(id: :z, upvotes: 7, created_at: @now)

    assert ids(Ranking.rank([x, y, z], now: @now)) == [:x, :y, :z]
    assert ids(Ranking.rank([z, x, y], now: @now)) == [:z, :x, :y]
  end