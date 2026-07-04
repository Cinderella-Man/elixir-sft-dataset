  test "gauge sets an exact value" do
    Metrics.gauge(:temp, 72)
    assert Metrics.get(:temp) == 72
  end