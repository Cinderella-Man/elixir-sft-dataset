  test "values above every boundary land only in the +Inf bucket" do
    Metrics.observe(:big, 5000)
    b = Metrics.get(:big).buckets
    assert b[10] == 0
    assert b[1000] == 0
    assert b[:infinity] == 1
    assert Metrics.get(:big).sum == 5000
  end