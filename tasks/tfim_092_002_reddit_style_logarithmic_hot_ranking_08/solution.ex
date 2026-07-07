  test "divisor is configurable" do
    it = item(upvotes: 1, created_at: @epoch + 90_000)
    # net 1 -> order 0 ; 90_000 / 45_000 = 2.0
    assert_in_delta Ranking.score(it, epoch: @epoch, divisor: 45_000), 2.0, 1.0e-9
    # 90_000 / 90_000 = 1.0
    assert_in_delta Ranking.score(it, epoch: @epoch, divisor: 90_000), 1.0, 1.0e-9
  end