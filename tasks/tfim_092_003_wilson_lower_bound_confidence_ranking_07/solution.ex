  test "adding a downvote lowers the score" do
    clean = Ranking.score(item(upvotes: 10, downvotes: 0))
    dinged = Ranking.score(item(upvotes: 10, downvotes: 1))
    assert dinged < clean
  end