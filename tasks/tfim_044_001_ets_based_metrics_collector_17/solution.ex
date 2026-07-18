  test "reset/1 returns :ok for counters, gauges and unknown metrics" do
    Metrics.increment(:ret_counter, 3)
    Metrics.gauge(:ret_g, 9)

    assert Metrics.reset(:ret_counter) == :ok
    assert Metrics.reset(:ret_g) == :ok
    assert Metrics.reset(:never_seen_before) == :ok
    assert :ok = Metrics.reset(:ret_counter)

    assert Metrics.get(:ret_counter) == 0
    assert Metrics.get(:ret_g) == 0
    assert Metrics.get(:never_seen_before) == 0
  end