  test "time term is additive and linear in elapsed seconds" do
    # net 1 -> order 0 ; created one divisor-worth of seconds after epoch -> +1.0
    it = item(upvotes: 1, created_at: @epoch + @divisor)
    assert_in_delta Ranking.score(it, opts()), 1.0, 1.0e-9
  end