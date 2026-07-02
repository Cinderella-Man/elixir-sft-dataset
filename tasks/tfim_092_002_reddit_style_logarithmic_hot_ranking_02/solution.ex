  test "at the epoch, score is just the logarithmic vote term" do
    # net 10 -> log10(10) = 1.0 ; net 100 -> log10(100) = 2.0
    assert_in_delta Ranking.score(item(upvotes: 10, created_at: @epoch), opts()), 1.0, 1.0e-9
    assert_in_delta Ranking.score(item(upvotes: 100, created_at: @epoch), opts()), 2.0, 1.0e-9
  end