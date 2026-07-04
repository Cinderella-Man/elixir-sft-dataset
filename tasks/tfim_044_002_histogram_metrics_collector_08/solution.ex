  test "custom bucket boundaries are honoured" do
    stop_supervised(Metrics)
    start_supervised!({Metrics, buckets: [1, 2, 3]})
    Metrics.observe(:x, 2)
    b = Metrics.get(:x).buckets
    assert b[1] == 0
    assert b[2] == 1
    assert b[3] == 1
    assert b[:infinity] == 1
  end