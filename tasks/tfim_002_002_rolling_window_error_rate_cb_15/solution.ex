  test "default window_size of 20 evicts the oldest outcome on the 21st call" do
    # Threshold 1.0 means only an all-error window trips, so the lone success
    # pins the exact call on which it is evicted — i.e. the window size.
    cb = start_cb(error_rate_threshold: 1.0, min_calls_in_window: 1)

    assert {:ok, :value} = RollingRateCircuitBreaker.call(cb, ok_fn())

    # 19 errors + that success = 20 outcomes → 19/20 < 1.0, still closed.
    for _ <- 1..19, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # The 21st call evicts the oldest outcome (the success): 20/20 = 1.0 → trip.
    assert {:error, :failure} = RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)
  end