  test "get/1 aggregates across all label combinations" do
    Metrics.increment(:requests, %{method: "GET"}, 3)
    Metrics.increment(:requests, %{method: "POST"}, 4)
    Metrics.increment(:requests, %{method: "PUT"}, 1)
    assert Metrics.get(:requests) == 8
  end