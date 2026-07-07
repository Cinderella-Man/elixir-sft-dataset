  test "a higher z (more confidence demanded) lowers the score" do
    it = item(upvotes: 10, downvotes: 2)
    s95 = Ranking.score(it, z: 1.96)
    s99 = Ranking.score(it, z: 2.58)
    assert s99 < s95
  end