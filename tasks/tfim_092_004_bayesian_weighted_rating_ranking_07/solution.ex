  test "a larger min_votes pulls a low-vote item more strongly toward the mean" do
    it = item(rating: 10.0, vote_count: 10)
    # m=25 -> (10/35)*10 + (25/35)*5 = 6.428571...
    # m=100 -> (10/110)*10 + (100/110)*5 = 5.454545...
    s_small_m = Ranking.score(it, mean: 5.0, min_votes: 25)
    s_large_m = Ranking.score(it, mean: 5.0, min_votes: 100)

    assert_in_delta s_small_m, 6.4285714, 1.0e-6
    assert_in_delta s_large_m, 5.4545454, 1.0e-6
    assert s_large_m < s_small_m
    assert s_large_m > 5.0
  end