  test "weights are configurable enough to flip the ordering" do
    fresh_mid = item(id: :fresh, upvotes: 10, created_at: @now)
    stale_high = item(id: :stale, upvotes: 100, created_at: @now - 200 * @hour)

    # Default-ish weights: raw votes dominate, stale_high wins.
    default_order = ids(Ranking.rank([fresh_mid, stale_high], now: @now))
    assert default_order == [:stale, :fresh]

    # Crush the vote weight and amplify recency: the fresh item overtakes.
    w = %{votes: 0.01, recency: 100.0, engagement: 0.0}
    flipped = ids(Ranking.rank([stale_high, fresh_mid], now: @now, weights: w))
    assert flipped == [:fresh, :stale]
  end