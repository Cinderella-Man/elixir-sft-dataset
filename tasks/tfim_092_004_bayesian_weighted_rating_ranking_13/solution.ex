  test "rank threads a non-default :min_votes through to every score" do
    p = item(id: :p, rating: 9.5, vote_count: 10)
    q = item(id: :q, rating: 9.0, vote_count: 100)
    r = item(id: :r, rating: 3.0, vote_count: 1000)

    # corpus mean = (9.5 + 9.0 + 3.0) / 3 = 7.1666...
    # m = 25 (default): p -> 7.8333..., q -> 8.6333... => q ahead of p.
    assert ids(Ranking.rank([p, q, r])) == [:q, :p, :r]

    # m = 1: barely any smoothing, so the raw ratings decide:
    #   p -> (10/11)*9.5 + (1/11)*7.1666... = 9.2878...
    #   q -> (100/101)*9.0 + (1/101)*7.1666... = 8.9818...  => p ahead of q.
    assert ids(Ranking.rank([p, q, r], min_votes: 1)) == [:p, :q, :r]
  end