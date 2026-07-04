  test "buckets are cumulative (less-than-or-equal)" do
    Metrics.observe(:lat, 5)
    Metrics.observe(:lat, 42)
    Metrics.observe(:lat, 42)
    b = Metrics.get(:lat).buckets
    assert b[10] == 1
    assert b[50] == 3
    assert b[100] == 3
    assert b[500] == 3
    assert b[1000] == 3
    assert b[:infinity] == 3
  end