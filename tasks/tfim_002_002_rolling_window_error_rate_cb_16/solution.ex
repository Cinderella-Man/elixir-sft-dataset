  test "a single failure trips when min_calls_in_window is 1 and threshold is 1.0" do
    # total (1) >= min_calls_in_window (1) and 1/1 = 1.0 >= 1.0 → trip.
    cb = start_cb(min_calls_in_window: 1, error_rate_threshold: 1.0)

    assert {:error, :failure} = RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)
  end