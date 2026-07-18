  test "rank scores with a caller-supplied :mean that differs from the corpus mean" do
    a = item(id: :a, rating: 9.0, vote_count: 100)
    b = item(id: :b, rating: 9.5, vote_count: 3)

    # Corpus mean = (9.0 + 9.5) / 2 = 9.25, m = 25:
    #   a -> (100/125)*9.0 + (25/125)*9.25  = 9.05
    #   b -> (3/28)*9.5   + (25/28)*9.25    = 9.2767...  => b outranks a.
    assert ids(Ranking.rank([a, b])) == [:b, :a]

    # With C = 0.0 supplied verbatim, the 3-vote item is crushed toward 0:
    #   a -> (100/125)*9.0 = 7.2
    #   b -> (3/28)*9.5    = 1.0178...      => a outranks b.
    assert ids(Ranking.rank([a, b], mean: 0.0)) == [:a, :b]
    assert ids(Ranking.rank([b, a], mean: 0.0)) == [:a, :b]
  end