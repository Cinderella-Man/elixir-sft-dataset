  test "series whose weights have all underflowed to zero reports empty" do
    start_server([])

    DecayPercentile.record(:u, 1)
    DecayPercentile.record(:u, 50)
    DecayPercentile.record(:u, 100)

    # 2000 half-lives: every 0.5 ^ (age / half_life) underflows to 0.0, so the
    # series holds samples but carries no weight at all.
    Clock.advance(2_000_000)

    assert {:error, :empty} = DecayPercentile.query(:u, 0.0)
    assert {:error, :empty} = DecayPercentile.query(:u, 0.5)
    assert {:error, :empty} = DecayPercentile.query(:u, 1.0)
    assert {:error, :empty} = DecayPercentile.total_weight(:u)
  end