  test "different metric names are completely independent" do
    Metrics.increment(:foo, 3)
    Metrics.gauge(:bar, 10)
    assert Metrics.get(:foo) == 3
    assert Metrics.get(:bar) == 10
  end