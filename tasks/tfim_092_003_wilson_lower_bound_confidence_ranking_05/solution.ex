  test "no votes scores exactly 0.0 and never raises" do
    assert Ranking.score(item(upvotes: 0, downvotes: 0)) === 0.0
  end