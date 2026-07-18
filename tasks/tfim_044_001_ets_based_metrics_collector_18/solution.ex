  test "all/0 returns a map of all metrics" do
    Metrics.increment(:a, 1)
    Metrics.gauge(:b, 42)
    result = Metrics.all()
    assert is_map(result)
    assert result[:a] == 1
    assert result[:b] == 42
  end