  test "unknown series is empty" do
    start_server([])
    assert {:error, :empty} = DecayPercentile.query(:nope, 0.5)
    assert {:error, :empty} = DecayPercentile.total_weight(:nope)
  end