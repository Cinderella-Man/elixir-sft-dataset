  test "score is rounded to exactly 7 decimal places" do
    # net 1 -> order 0.0 ; 1 second / divisor 3 -> 0.333333... -> 0.3333333
    it = item(upvotes: 1, created_at: @epoch + 1)
    assert Ranking.score(it, epoch: @epoch, divisor: 3) === 0.3333333

    # 2 seconds / divisor 3 -> 0.666666... -> 0.6666667 (rounds up at the 7th place)
    it2 = item(upvotes: 1, created_at: @epoch + 2)
    assert Ranking.score(it2, epoch: @epoch, divisor: 3) === 0.6666667
  end