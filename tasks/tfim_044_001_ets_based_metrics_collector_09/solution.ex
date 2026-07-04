  test "gauge can be set to 0" do
    Metrics.gauge(:active, 7)
    Metrics.gauge(:active, 0)
    assert Metrics.get(:active) == 0
  end