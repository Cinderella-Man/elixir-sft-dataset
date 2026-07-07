  test "highly-upvoted item ranks above a low-vote item of equal age" do
    high = item(id: :high, upvotes: 100, created_at: @now)
    low = item(id: :low, upvotes: 2, created_at: @now)

    assert Ranking.score(high, now: @now) > Ranking.score(low, now: @now)
  end