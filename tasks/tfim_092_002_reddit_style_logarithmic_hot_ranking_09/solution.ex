  test "newer item ranks above an older one with equal votes" do
    recent = item(id: :recent, upvotes: 50, created_at: @epoch)
    old = item(id: :old, upvotes: 50, created_at: @epoch - 100 * @divisor)
    assert Ranking.score(recent, opts()) > Ranking.score(old, opts())
  end