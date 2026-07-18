  test "omitting :z is identical to passing z: 1.96 for both score and rank" do
    it = item(upvotes: 12, downvotes: 5)
    assert Ranking.score(it) === Ranking.score(it, z: 1.96)
    assert Ranking.score(item(upvotes: 0, downvotes: 0)) === Ranking.score(item([]), z: 1.96)

    a = item(id: :a, upvotes: 12, downvotes: 5)
    b = item(id: :b, upvotes: 3, downvotes: 0)
    c = item(id: :c, upvotes: 1, downvotes: 4)
    assert ids(Ranking.rank([c, b, a])) == ids(Ranking.rank([c, b, a], z: 1.96))
  end