  test "recency is 1.0 at age zero and 0.5 at one half-life" do
    w = %{votes: 0.0, recency: 1.0, engagement: 0.0}

    fresh = item(created_at: @now)
    aged = item(created_at: @now - 12 * @hour)

    assert_in_delta Ranking.score(fresh, now: @now, weights: w, half_life_hours: 12), 1.0, 1.0e-9
    assert_in_delta Ranking.score(aged, now: @now, weights: w, half_life_hours: 12), 0.5, 1.0e-9
  end