  test "more votes at the same ratio raise the score" do
    small = Ranking.score(item(upvotes: 1, downvotes: 0))
    big = Ranking.score(item(upvotes: 10, downvotes: 0))
    assert big > small
  end