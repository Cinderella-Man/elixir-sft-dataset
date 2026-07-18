  test "half_life_hours defaults to 12 when the option is omitted" do
    w = %{votes: 0.0, recency: 1.0, engagement: 0.0}

    aged = item(created_at: @now - 12 * @hour)
    double_aged = item(created_at: @now - 24 * @hour)

    assert_in_delta Ranking.score(aged, now: @now, weights: w), 0.5, 1.0e-9
    assert_in_delta Ranking.score(double_aged, now: @now, weights: w), 0.25, 1.0e-9
  end