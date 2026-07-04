  test "count, sum and average accumulate across observations" do
    Metrics.observe(:lat, 5)
    Metrics.observe(:lat, 42)
    Metrics.observe(:lat, 42)
    summary = Metrics.get(:lat)
    assert summary.count == 3
    assert summary.sum == 89
    assert_in_delta summary.average, 89 / 3, 0.0001
  end