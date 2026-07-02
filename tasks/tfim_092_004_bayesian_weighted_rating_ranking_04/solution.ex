  test "an item with no votes scores exactly the prior mean" do
    it = item(rating: 10.0, vote_count: 0)
    assert_in_delta Ranking.score(it, mean: 6.0, min_votes: 25), 6.0, 1.0e-9
  end