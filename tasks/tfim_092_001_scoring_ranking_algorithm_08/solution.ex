  test "recent item ranks above an older item with equal votes" do
    recent = item(id: :recent, upvotes: 100, created_at: @now)
    old = item(id: :old, upvotes: 100, created_at: @now - 100 * @hour)

    assert Ranking.score(recent, now: @now) > Ranking.score(old, now: @now)
  end