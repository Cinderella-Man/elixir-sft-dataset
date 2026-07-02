  test "increment adds the given amount" do
    Metrics.increment(:hits, 5)
    Metrics.increment(:hits, 3)
    assert Metrics.get(:hits) == 8
  end