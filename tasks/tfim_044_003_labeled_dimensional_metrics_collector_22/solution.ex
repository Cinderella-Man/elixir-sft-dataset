  test "gauge, get, series, reset and all canonicalise reordered label maps" do
    Metrics.gauge(:temp, %{a: 1, b: 2}, 10)
    Metrics.gauge(:temp, %{b: 2, a: 1}, 25)

    assert Metrics.get(:temp, %{b: 2, a: 1}) == 25
    assert Metrics.get(:temp) == 25
    assert Metrics.series(:temp) == [%{labels: %{a: 1, b: 2}, value: 25}]

    Metrics.reset(:temp, %{b: 2, a: 1})
    assert Metrics.get(:temp, %{a: 1, b: 2}) == 0
    assert Metrics.all() == %{{:temp, %{a: 1, b: 2}} => 0}
  end