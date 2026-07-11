  test "a fresh sample outweighs an old one and shifts the median" do
    start_server([])

    # old, low value at t=0
    DecayPercentile.record(:t, 1)

    # 3 half-lives later: old weight = 0.125, new weight = 1.0
    Clock.advance(3_000)
    DecayPercentile.record(:t, 100)

    # W = 1.125, target for p50 = 0.5625; cumulative at 1 is only 0.125,
    # so the median is pulled all the way up to the fresh sample.
    assert {:ok, 100} = DecayPercentile.query(:t, 0.50)
  end