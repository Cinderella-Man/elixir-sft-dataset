  test "single sample returns that sample for any percentile" do
    start_server([])
    Percentile.record(:one, 42)

    assert {:ok, 42} = Percentile.query(:one, 0.0)
    assert {:ok, 42} = Percentile.query(:one, 0.5)
    assert {:ok, 42} = Percentile.query(:one, 1.0)
  end