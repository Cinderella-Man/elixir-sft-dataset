  test "rank threads min_votes 0 so a no-vote item still scores at the corpus mean" do
    a = item(id: :a, rating: 9.0, vote_count: 10)
    b = item(id: :b, rating: 5.0, vote_count: 0)
    c = item(id: :c, rating: 1.0, vote_count: 10)

    # corpus mean = (9.0 + 5.0 + 1.0) / 3 = 5.0, m = 0:
    #   a -> (10/10)*9.0 = 9.0
    #   b -> v + m == 0  = 5.0 (the corpus mean, no raise)
    #   c -> (10/10)*1.0 = 1.0
    assert ids(Ranking.rank([c, b, a], min_votes: 0)) == [:a, :b, :c]
  end