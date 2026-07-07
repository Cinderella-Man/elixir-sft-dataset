  test "negative net votes make the vote term negative" do
    it = item(upvotes: 0, downvotes: 10, created_at: @epoch)
    # sign = -1, order = log10(10) = 1.0 -> -1.0
    assert_in_delta Ranking.score(it, opts()), -1.0, 1.0e-9
  end