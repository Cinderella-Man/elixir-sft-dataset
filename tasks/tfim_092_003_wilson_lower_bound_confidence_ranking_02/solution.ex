  test "1 upvote / 0 downvotes matches the known Wilson lower bound" do
    assert_in_delta Ranking.score(item(upvotes: 1, downvotes: 0)), 0.2065432, 1.0e-6
  end