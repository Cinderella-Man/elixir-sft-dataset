  test "10 upvotes / 0 downvotes matches the known Wilson lower bound" do
    assert_in_delta Ranking.score(item(upvotes: 10, downvotes: 0)), 0.7224598, 1.0e-6
  end