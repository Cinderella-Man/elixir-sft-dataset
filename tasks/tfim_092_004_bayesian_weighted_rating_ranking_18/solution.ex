  test "a no-vote item lands at the corpus mean between a stronger and a weaker item" do
    a = item(id: :a, rating: 9.0, vote_count: 100)
    b = item(id: :b, rating: 6.0, vote_count: 0)
    c = item(id: :c, rating: 3.0, vote_count: 100)

    # corpus mean = (9.0 + 6.0 + 3.0) / 3 = 6.0, m = 25 (default):
    #   a -> (100/125)*9.0 + (25/125)*6.0 = 8.4
    #   b -> no votes                     = 6.0  (exactly the corpus mean)
    #   c -> (100/125)*3.0 + (25/125)*6.0 = 3.6
    assert ids(Ranking.rank([c, b, a])) == [:a, :b, :c]
    assert_in_delta Ranking.score(b, mean: 6.0), 6.0, 1.0e-9
  end