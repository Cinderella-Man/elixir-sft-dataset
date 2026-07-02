  test "increment defaults amount to 1" do
    Metrics.increment(:clicks)
    Metrics.increment(:clicks)
    Metrics.increment(:clicks)
    assert Metrics.get(:hits) == nil
    assert Metrics.get(:clicks) == 3
  end