  test "ties on score are broken by vote_count descending" do
    # rating == mean => score == mean regardless of vote_count => scores tie.
    low = item(id: :low, rating: 8.0, vote_count: 5)
    high = item(id: :high, rating: 8.0, vote_count: 100)

    assert ids(Ranking.rank([low, high], mean: 8.0, min_votes: 25)) == [:high, :low]
    assert ids(Ranking.rank([high, low], mean: 8.0, min_votes: 25)) == [:high, :low]
  end