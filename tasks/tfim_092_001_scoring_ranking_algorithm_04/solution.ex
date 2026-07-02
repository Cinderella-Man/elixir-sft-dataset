  test "net votes can be negative and drag the score down" do
    up = item(upvotes: 20, downvotes: 0)
    down = item(upvotes: 0, downvotes: 20)

    w = %{votes: 1.0, recency: 0.0, engagement: 0.0}
    assert_in_delta Ranking.score(up, now: @now, weights: w), 20.0, 1.0e-9
    assert_in_delta Ranking.score(down, now: @now, weights: w), -20.0, 1.0e-9
  end