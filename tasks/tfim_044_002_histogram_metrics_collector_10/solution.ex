  test "reset erases a histogram entirely" do
    Metrics.observe(:gone, 10)
    assert Metrics.get(:gone).count == 1
    Metrics.reset(:gone)
    assert Metrics.get(:gone) == nil
    assert Metrics.all()[:gone] == nil
  end