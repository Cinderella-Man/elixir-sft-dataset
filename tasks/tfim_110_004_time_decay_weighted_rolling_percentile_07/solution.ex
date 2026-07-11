  test "total_weight reflects exponential decay of a single sample" do
    start_server([])
    DecayPercentile.record(:w, 5)

    assert {:ok, w0} = DecayPercentile.total_weight(:w)
    assert_in_delta w0, 1.0, 1.0e-9

    Clock.advance(1_000)
    assert {:ok, w1} = DecayPercentile.total_weight(:w)
    assert_in_delta w1, 0.5, 1.0e-9

    Clock.advance(1_000)
    assert {:ok, w2} = DecayPercentile.total_weight(:w)
    assert_in_delta w2, 0.25, 1.0e-9
  end