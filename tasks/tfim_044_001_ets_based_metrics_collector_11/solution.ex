  test "reset sets a gauge back to 0" do
    Metrics.gauge(:level, 99)
    Metrics.reset(:level)
    assert Metrics.get(:level) == 0
  end