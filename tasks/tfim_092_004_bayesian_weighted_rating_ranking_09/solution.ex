  test "an explicit :mean overrides the computed corpus mean" do
    a = item(id: :a, rating: 9.0, vote_count: 100)
    _b = item(id: :b, rating: 9.5, vote_count: 3)

    # With mean forced very high, the low-vote high-rating item is pulled UP
    # toward the mean less harshly than the high-vote one, but both are near
    # the mean; verify the score uses 12.0, not the corpus mean of 9.25.
    assert_in_delta Ranking.score(a, mean: 12.0), 9.0 * (100 / 125) + 12.0 * (25 / 125), 1.0e-9
  end