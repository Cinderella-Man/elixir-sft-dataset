  test "underflow in one series leaves a freshly recorded series unaffected" do
    start_server([])

    DecayPercentile.record(:old, 1)
    Clock.advance(2_000_000)
    DecayPercentile.record(:new, 42)

    assert {:error, :empty} = DecayPercentile.query(:old, 0.5)
    assert {:error, :empty} = DecayPercentile.total_weight(:old)
    assert {:ok, 42} = DecayPercentile.query(:new, 0.5)
  end