  test "min_calls_in_window above window_size disables automatic tripping" do
    cb = start_cb(window_size: 5, min_calls_in_window: 10, error_rate_threshold: 0.5)

    for _ <- 1..30, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end