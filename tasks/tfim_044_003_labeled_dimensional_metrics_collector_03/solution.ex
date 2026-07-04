  test "same name with different labels are independent series" do
    Metrics.increment(:requests, %{method: "GET"})
    Metrics.increment(:requests, %{method: "GET"})
    Metrics.increment(:requests, %{method: "POST"})
    assert Metrics.get(:requests, %{method: "GET"}) == 2
    assert Metrics.get(:requests, %{method: "POST"}) == 1
  end