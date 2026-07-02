  test "score is a float" do
    assert is_float(Ranking.score(item(rating: 7.0, vote_count: 3), mean: 6.0))
  end