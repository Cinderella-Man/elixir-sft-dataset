  test "gauge with labels overwrites the series" do
    Metrics.gauge(:temp, %{room: "kitchen"}, 20)
    Metrics.gauge(:temp, %{room: "kitchen"}, 25)
    assert Metrics.get(:temp, %{room: "kitchen"}) == 25
  end