  test "items created before the epoch get a negative time term" do
    # net 1 -> order 0.0 ; -90_000 / 45_000 -> -2.0
    before = item(upvotes: 1, created_at: @epoch - 90_000)
    assert_in_delta Ranking.score(before, opts()), -2.0, 1.0e-9

    # net 10 -> order 1.0 ; -45_000 / 45_000 -> -1.0 -> total 0.0
    mixed = item(upvotes: 10, created_at: @epoch - 45_000)
    assert_in_delta Ranking.score(mixed, opts()), 0.0, 1.0e-9
  end