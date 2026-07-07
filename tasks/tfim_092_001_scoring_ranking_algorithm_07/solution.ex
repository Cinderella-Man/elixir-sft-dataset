  test "future created_at is clamped to age zero (recency never exceeds 1.0)" do
    w = %{votes: 0.0, recency: 1.0, engagement: 0.0}
    future = item(created_at: @now + 10_000)
    assert_in_delta Ranking.score(future, now: @now, weights: w), 1.0, 1.0e-9
  end