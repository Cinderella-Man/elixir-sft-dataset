  test "score uses the default divisor of 45_000 when :divisor is not given" do
    # net 1 -> order 0.0 ; 45_000 seconds after the given epoch -> +1.0
    it = item(upvotes: 1, created_at: @epoch + 45_000)
    assert_in_delta Ranking.score(it, epoch: @epoch), 1.0, 1.0e-9

    # 90_000 seconds -> +2.0 under the default divisor
    it2 = item(upvotes: 1, created_at: @epoch + 90_000)
    assert_in_delta Ranking.score(it2, epoch: @epoch), 2.0, 1.0e-9
  end