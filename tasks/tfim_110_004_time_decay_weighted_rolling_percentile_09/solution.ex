  test "reset clears a series" do
    start_server([])
    for v <- 1..10, do: DecayPercentile.record(:r, v)
    assert :ok = DecayPercentile.reset(:r)
    assert {:error, :empty} = DecayPercentile.query(:r, 0.5)
  end