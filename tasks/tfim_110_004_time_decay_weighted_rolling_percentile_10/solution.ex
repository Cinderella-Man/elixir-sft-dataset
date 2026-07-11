  test "series are independent" do
    start_server([])
    DecayPercentile.record(:a, 1)
    DecayPercentile.record(:b, 999)

    assert {:ok, 1} = DecayPercentile.query(:a, 0.5)
    assert {:ok, 999} = DecayPercentile.query(:b, 0.5)

    DecayPercentile.reset(:a)
    assert {:error, :empty} = DecayPercentile.query(:a, 0.5)
    assert {:ok, 999} = DecayPercentile.query(:b, 0.5)
  end