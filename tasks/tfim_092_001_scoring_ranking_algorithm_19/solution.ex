  test "a partial weights map is merged over the defaults, leaving other weights at 1.0" do
    # net = 10 ; recency weight zeroed ; engagement = 5/100 = 0.05
    # score = 1.0*10 + 0.0*recency + 1.0*0.05 = 10.05
    it =
      item(
        upvotes: 10,
        downvotes: 0,
        created_at: @now - 12 * @hour,
        view_count: 100,
        comment_count: 5
      )

    assert_in_delta Ranking.score(it, now: @now, weights: %{recency: 0.0}), 10.05, 1.0e-9
  end