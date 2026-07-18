  test "reset/1 zeroes every series under the name" do
    Metrics.increment(:requests, %{method: "GET"}, 5)
    Metrics.increment(:requests, %{method: "POST"}, 9)
    Metrics.reset(:requests)
    assert Metrics.get(:requests) == 0
    assert Metrics.get(:requests, %{method: "GET"}) == 0
    assert Metrics.get(:requests, %{method: "POST"}) == 0
  end