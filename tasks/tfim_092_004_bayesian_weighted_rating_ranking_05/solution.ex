  test "no votes with default options never raises and yields the default mean 0.0" do
    assert Ranking.score(item(rating: 5.0, vote_count: 0)) === 0.0
  end