  test "reset on unknown metric sets it to 0" do
    Metrics.reset(:brand_new)
    assert Metrics.get(:brand_new) == 0
  end