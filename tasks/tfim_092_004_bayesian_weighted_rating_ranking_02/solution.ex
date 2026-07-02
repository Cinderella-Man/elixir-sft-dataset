  test "score matches the weighted-rating formula with explicit mean/min_votes" do
    # (100/125)*9.0 + (25/125)*8.5 = 7.2 + 1.7 = 8.9
    it = item(rating: 9.0, vote_count: 100)
    assert_in_delta Ranking.score(it, mean: 8.5, min_votes: 25), 8.9, 1.0e-9
  end