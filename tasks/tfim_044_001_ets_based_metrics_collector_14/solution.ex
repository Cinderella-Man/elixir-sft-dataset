  test "increment/2 returns :ok rather than the counter's new value" do
    assert Metrics.increment(:ret_val) == :ok
    assert Metrics.increment(:ret_val, 4) == :ok
    assert Metrics.increment(:ret_val, 0) == :ok
    assert Metrics.get(:ret_val) == 5
  end