  test "series lists every label combination with its value" do
    Metrics.increment(:requests, %{method: "GET"}, 2)
    Metrics.increment(:requests, %{method: "POST"}, 5)
    series = Metrics.series(:requests)
    assert length(series) == 2
    assert %{labels: %{method: "GET"}, value: 2} in series
    assert %{labels: %{method: "POST"}, value: 5} in series
  end