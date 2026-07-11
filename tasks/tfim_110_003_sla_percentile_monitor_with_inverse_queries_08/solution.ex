  test "expired samples drop out of query, rank, and count_above" do
    start_server(window_ms: 1_000)

    for v <- 1..50, do: RankPercentile.record(:t, v)

    Clock.advance(1_000)

    for v <- 60..69, do: RankPercentile.record(:t, v)

    # only [60..69] are live now
    assert {:ok, 64} = RankPercentile.query(:t, 0.50)
    assert {:ok, 0.5} = RankPercentile.rank(:t, 64)
    assert {:ok, 5} = RankPercentile.count_above(:t, 64)
  end