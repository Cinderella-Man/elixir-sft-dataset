  test "all is keyed by {name, labels}" do
    Metrics.increment(:a, %{k: 1}, 3)
    Metrics.gauge(:b, %{k: 2}, 42)
    result = Metrics.all()
    assert result[{:a, %{k: 1}}] == 3
    assert result[{:b, %{k: 2}}] == 42
  end