  test "net_votes of zero contributes nothing from the vote term" do
    it = item(upvotes: 5, downvotes: 5, created_at: @epoch)
    assert_in_delta Ranking.score(it, opts()), 0.0, 1.0e-9
  end