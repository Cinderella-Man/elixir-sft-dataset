  test "a fully expired series behaves exactly like a never-recorded one" do
    start_server(window_ms: 500)

    for v <- 1..3, do: RankPercentile.record(:gone, v)

    assert {:ok, 2} = RankPercentile.query(:gone, 0.5)

    Clock.advance(500)

    assert {:error, :empty} = RankPercentile.query(:gone, 0.5)
    assert {:error, :empty} = RankPercentile.rank(:gone, 2)
    assert {:ok, 0} = RankPercentile.count_above(:gone, 0)

    # identical answers for a series that was never recorded at all
    assert {:error, :empty} = RankPercentile.query(:never, 0.5)
    assert {:error, :empty} = RankPercentile.rank(:never, 2)
    assert {:ok, 0} = RankPercentile.count_above(:never, 0)
  end