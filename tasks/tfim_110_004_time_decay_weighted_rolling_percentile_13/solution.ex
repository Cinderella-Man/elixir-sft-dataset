  test "recording after total underflow makes the series report the fresh sample" do
    start_server([])

    DecayPercentile.record(:u2, 1)
    Clock.advance(2_000_000)
    assert {:error, :empty} = DecayPercentile.query(:u2, 0.5)

    # The fresh sample has weight 1.0 while the underflowed one contributes 0.0,
    # so it alone determines every percentile.
    DecayPercentile.record(:u2, 7)

    assert {:ok, 7} = DecayPercentile.query(:u2, 0.0)
    assert {:ok, 7} = DecayPercentile.query(:u2, 1.0)
    assert {:ok, w} = DecayPercentile.total_weight(:u2)
    assert_in_delta w, 1.0, 1.0e-9
  end