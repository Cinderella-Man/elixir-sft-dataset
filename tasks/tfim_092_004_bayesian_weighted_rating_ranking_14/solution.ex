  test "fully-equal items preserve original input order (stable)" do
    x = item(id: :x, rating: 7.0, vote_count: 10)
    y = item(id: :y, rating: 7.0, vote_count: 10)
    z = item(id: :z, rating: 7.0, vote_count: 10)

    assert ids(Ranking.rank([x, y, z], mean: 7.0)) == [:x, :y, :z]
    assert ids(Ranking.rank([z, x, y], mean: 7.0)) == [:z, :x, :y]
  end