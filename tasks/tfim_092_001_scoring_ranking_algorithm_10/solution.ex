  test "higher comment/view engagement ratio increases the score" do
    w = %{votes: 0.0, recency: 0.0, engagement: 1.0}

    engaged = item(view_count: 100, comment_count: 50)
    meh = item(view_count: 100, comment_count: 10)

    assert_in_delta Ranking.score(engaged, now: @now, weights: w), 0.5, 1.0e-9
    assert_in_delta Ranking.score(meh, now: @now, weights: w), 0.1, 1.0e-9

    assert Ranking.score(engaged, now: @now, weights: w) >
             Ranking.score(meh, now: @now, weights: w)
  end