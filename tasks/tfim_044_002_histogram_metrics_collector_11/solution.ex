  test "reset of one histogram leaves others intact" do
    Metrics.observe(:keep, 3)
    Metrics.observe(:drop, 3)
    Metrics.reset(:drop)
    assert Metrics.get(:drop) == nil
    assert Metrics.get(:keep).count == 1
  end