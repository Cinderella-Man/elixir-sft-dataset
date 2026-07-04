  test "get/2 returns nil for an unknown series" do
    Metrics.increment(:requests, %{method: "GET"})
    assert Metrics.get(:requests, %{method: "DELETE"}) == nil
  end