  test "increment creates a counter starting at 1" do
    assert :ok = Metrics.increment(:hits)
    assert Metrics.get(:hits) == 1
  end