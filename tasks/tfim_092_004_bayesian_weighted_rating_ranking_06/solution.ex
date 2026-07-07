  test "zero denominator (min_votes 0, no votes) returns the mean without raising" do
    it = item(rating: 4.0, vote_count: 0)
    assert_in_delta Ranking.score(it, mean: 3.5, min_votes: 0), 3.5, 1.0e-9
  end