  test "proven quality beats uncertain perfection" do
    perfect_tiny = Ranking.score(item(upvotes: 1, downvotes: 0))
    strong_large = Ranking.score(item(upvotes: 50, downvotes: 10))
    assert strong_large > perfect_tiny
  end