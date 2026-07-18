  test "rank passes half_life_hours through to scoring and it can change the order" do
    w = %{votes: 0.1, recency: 1.0, engagement: 0.0}

    old = item(id: :old, upvotes: 5, created_at: @now - 24 * @hour)
    fresh = item(id: :fresh, upvotes: 0, created_at: @now)

    # Short half-life: the old item's recency collapses -> 0.5 vs 1.0.
    short = ids(Ranking.rank([old, fresh], now: @now, weights: w, half_life_hours: 1))
    assert short == [:fresh, :old]

    # Long half-life: the old item keeps most of its recency -> ~1.207 vs 1.0.
    long = ids(Ranking.rank([old, fresh], now: @now, weights: w, half_life_hours: 48))
    assert long == [:old, :fresh]
  end