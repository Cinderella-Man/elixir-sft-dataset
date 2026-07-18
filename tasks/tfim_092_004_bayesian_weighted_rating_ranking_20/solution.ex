  test "score with no options at all uses the documented defaults m = 25 and C = 0.0" do
    # (25/50)*8.0 + (25/50)*0.0 = 4.0
    assert_in_delta Ranking.score(item(rating: 8.0, vote_count: 25)), 4.0, 1.0e-9
    # (75/100)*8.0 + (25/100)*0.0 = 6.0
    assert_in_delta Ranking.score(item(rating: 8.0, vote_count: 75)), 6.0, 1.0e-9
  end