  test "rating equal to the mean scores exactly the mean at every vote count" do
    for v <- [0, 1, 25, 1_000, 100_000] do
      it = item(rating: 8.5, vote_count: v)
      assert_in_delta Ranking.score(it, mean: 8.5, min_votes: 25), 8.5, 1.0e-9
      assert_in_delta Ranking.score(it, mean: 8.5, min_votes: 100), 8.5, 1.0e-9
    end
  end