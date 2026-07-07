  test "larger sample with a higher ratio wins convincingly" do
    a = Ranking.score(item(upvotes: 100, downvotes: 10))
    b = Ranking.score(item(upvotes: 5, downvotes: 1))
    assert a > b
  end