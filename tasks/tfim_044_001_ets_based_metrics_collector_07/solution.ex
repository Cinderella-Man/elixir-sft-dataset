  test "gauge overwrites on repeated calls" do
    Metrics.gauge(:temp, 72)
    Metrics.gauge(:temp, 55)
    Metrics.gauge(:temp, 100)
    assert Metrics.get(:temp) == 100
  end