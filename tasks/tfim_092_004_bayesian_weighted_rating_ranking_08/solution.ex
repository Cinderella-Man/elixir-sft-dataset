  test "rank computes the corpus mean and pulls low-vote items down" do
    a = item(id: :a, rating: 9.0, vote_count: 100)
    b = item(id: :b, rating: 9.5, vote_count: 3)
    c = item(id: :c, rating: 7.0, vote_count: 1000)

    # corpus mean = (9.0 + 9.5 + 7.0) / 3 = 8.5, min_votes = 25 (default)
    ranked = Ranking.rank([b, c, a])
    assert ids(ranked) == [:a, :b, :c]

    # And the actual scores against the auto-computed mean:
    assert_in_delta Ranking.score(a, mean: 8.5), 8.9, 1.0e-9
    assert_in_delta Ranking.score(b, mean: 8.5), 8.6071428, 1.0e-6
    assert_in_delta Ranking.score(c, mean: 8.5), 7.0365853, 1.0e-6
  end