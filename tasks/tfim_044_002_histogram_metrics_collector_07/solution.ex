  test "a value exactly on a boundary is included at that boundary" do
    Metrics.observe(:edge, 50)
    b = Metrics.get(:edge).buckets
    assert b[10] == 0
    assert b[50] == 1
    assert b[100] == 1
  end