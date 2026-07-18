  test "time and count windows both apply when combined" do
    start_server(window_ms: 1_000, max_samples: 3)

    for v <- 1..5, do: RankPercentile.record(:m, v)

    # count window keeps only [3, 4, 5]
    assert {:ok, 3} = RankPercentile.query(:m, 0.0)
    assert {:ok, 5} = RankPercentile.query(:m, 1.0)
    assert {:ok, 2} = RankPercentile.count_above(:m, 3)
    assert {:ok, q} = RankPercentile.rank(:m, 3)
    assert_in_delta q, 1 / 3, 0.000_001

    # the time window then expires the survivors too
    Clock.advance(1_000)
    assert {:error, :empty} = RankPercentile.query(:m, 0.5)
    assert {:error, :empty} = RankPercentile.rank(:m, 3)
    assert {:ok, 0} = RankPercentile.count_above(:m, 0)
  end