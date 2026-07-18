  test "gauge/2 returns :ok on create and on overwrite" do
    assert Metrics.gauge(:ret_gauge, 1) == :ok
    assert Metrics.gauge(:ret_gauge, 2) == :ok
    assert :ok = Metrics.gauge(:ret_gauge, -5)
    assert Metrics.get(:ret_gauge) == -5
  end