  test "a single observation produces count 1 and matching sum" do
    assert :ok = Metrics.observe(:lat, 42)
    summary = Metrics.get(:lat)
    assert summary.count == 1
    assert summary.sum == 42
    assert_in_delta summary.average, 42.0, 0.0001
  end