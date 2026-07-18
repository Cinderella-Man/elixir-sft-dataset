  test "reset/1 leaves series recorded under other names untouched" do
    Metrics.increment(:requests, %{method: "GET"}, 5)
    Metrics.increment(:errors, %{method: "GET"}, 7)
    Metrics.gauge(:errors, 3)

    Metrics.reset(:requests)

    assert Metrics.get(:requests) == 0
    assert Metrics.get(:errors, %{method: "GET"}) == 7
    assert Metrics.get(:errors, %{}) == 3
    assert Metrics.get(:errors) == 10
  end