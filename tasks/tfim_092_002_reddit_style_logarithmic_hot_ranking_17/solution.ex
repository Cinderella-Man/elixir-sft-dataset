  test "score uses the default epoch when :epoch is not given" do
    # net 10 -> order 1.0 ; created exactly at the default epoch -> time term 0.0
    at_default_epoch = item(upvotes: 10, created_at: 1_134_028_003)
    assert_in_delta Ranking.score(at_default_epoch), 1.0, 1.0e-9

    # one default-divisor of seconds later -> +1.0 from the time term
    later = item(upvotes: 10, created_at: 1_134_028_003 + 45_000)
    assert_in_delta Ranking.score(later), 2.0, 1.0e-9
  end