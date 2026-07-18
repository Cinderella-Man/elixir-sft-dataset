  test "a sample stays live until elapsed time reaches window_ms exactly" do
    start_server(window_ms: 1_000)

    RankPercentile.record(:edge, 7)

    Clock.advance(999)
    assert {:ok, 7} = RankPercentile.query(:edge, 0.5)
    assert {:ok, 1.0} = RankPercentile.rank(:edge, 7)
    assert {:ok, 1} = RankPercentile.count_above(:edge, 6)

    # now - t == window_ms is no longer strictly less than the window
    Clock.advance(1)
    assert {:error, :empty} = RankPercentile.query(:edge, 0.5)
    assert {:error, :empty} = RankPercentile.rank(:edge, 7)
    assert {:ok, 0} = RankPercentile.count_above(:edge, 6)
  end