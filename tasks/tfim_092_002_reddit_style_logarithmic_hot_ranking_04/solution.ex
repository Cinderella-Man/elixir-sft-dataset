  test "vote term grows logarithmically (10x votes adds a constant)" do
    s10 = Ranking.score(item(upvotes: 10, created_at: @epoch), opts())
    s100 = Ranking.score(item(upvotes: 100, created_at: @epoch), opts())
    s1000 = Ranking.score(item(upvotes: 1000, created_at: @epoch), opts())

    assert_in_delta s100 - s10, 1.0, 1.0e-9
    assert_in_delta s1000 - s100, 1.0, 1.0e-9
  end