  test "query rejects percentiles outside the documented range" do
    start_server([])
    for v <- 1..10, do: RankPercentile.record(:g, v)

    assert_raise FunctionClauseError, fn -> RankPercentile.query(:g, 1.5) end
    assert_raise FunctionClauseError, fn -> RankPercentile.query(:g, -0.5) end

    # the boundaries themselves remain accepted
    assert {:ok, 1} = RankPercentile.query(:g, 0.0)
    assert {:ok, 10} = RankPercentile.query(:g, 1.0)
  end