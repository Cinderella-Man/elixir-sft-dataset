  test "ties on score are broken by created_at descending" do
    w = %{votes: 1.0, recency: 0.0, engagement: 0.0}

    older = item(id: :older, upvotes: 5, created_at: @now - 50 * @hour)
    newer = item(id: :newer, upvotes: 5, created_at: @now - 1 * @hour)

    # Equal scores (recency/engagement zeroed, same net votes) -> newer first.
    assert ids(Ranking.rank([older, newer], now: @now, weights: w)) == [:newer, :older]
    assert ids(Ranking.rank([newer, older], now: @now, weights: w)) == [:newer, :older]
  end