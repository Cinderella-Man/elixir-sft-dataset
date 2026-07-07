  test "zero view_count yields zero engagement and never raises" do
    w = %{votes: 0.0, recency: 0.0, engagement: 1.0}
    it = item(view_count: 0, comment_count: 25)
    assert_in_delta Ranking.score(it, now: @now, weights: w), 0.0, 1.0e-9
  end