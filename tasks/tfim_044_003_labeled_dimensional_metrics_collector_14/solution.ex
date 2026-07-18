  test "reset/2 zeroes one specific series" do
    Metrics.increment(:requests, %{method: "GET"}, 5)
    Metrics.increment(:requests, %{method: "POST"}, 9)
    Metrics.reset(:requests, %{method: "GET"})
    assert Metrics.get(:requests, %{method: "GET"}) == 0
    assert Metrics.get(:requests, %{method: "POST"}) == 9
  end