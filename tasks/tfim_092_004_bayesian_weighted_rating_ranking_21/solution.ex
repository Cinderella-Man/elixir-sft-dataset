  test "score returns a float in the zero-denominator branch given an integer mean" do
    it = item(rating: 4, vote_count: 0)
    assert is_float(Ranking.score(it, mean: 3, min_votes: 0))
    assert Ranking.score(it, mean: 3, min_votes: 0) === 3.0
    assert is_float(Ranking.score(item(rating: 4, vote_count: 10), mean: 3, min_votes: 0))
  end