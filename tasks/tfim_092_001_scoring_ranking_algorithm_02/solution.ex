  test "score matches the documented formula with default options" do
    # net = 10 - 4 = 6 ; age 0 -> recency 1.0 ; engagement 5/100 = 0.05
    # score = 1.0*6 + 1.0*1.0 + 1.0*0.05 = 7.05
    it = item(upvotes: 10, downvotes: 4, view_count: 100, comment_count: 5)
    assert_in_delta Ranking.score(it, now: @now), 7.05, 1.0e-9
  end