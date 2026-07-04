  test "gauge can decrease" do
    Metrics.gauge(:queue_depth, 50)
    Metrics.gauge(:queue_depth, 10)
    assert Metrics.get(:queue_depth) == 10
  end