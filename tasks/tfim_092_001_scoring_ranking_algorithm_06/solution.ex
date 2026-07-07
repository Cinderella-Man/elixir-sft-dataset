  test "half_life_hours is configurable" do
    w = %{votes: 0.0, recency: 1.0, engagement: 0.0}
    it = item(created_at: @now - 6 * @hour)

    # Age 6h with a 6h half-life -> recency 0.5
    assert_in_delta Ranking.score(it, now: @now, weights: w, half_life_hours: 6), 0.5, 1.0e-9
  end