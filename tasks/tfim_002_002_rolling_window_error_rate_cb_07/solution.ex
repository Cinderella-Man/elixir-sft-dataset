  test "rolling window evicts old outcomes and can un-trip risk as errors age out", %{cb: cb} do
    # Fill window with 10 successes
    for _ <- 1..10, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # Adding 4 errors: window is [4 errors, 6 successes] = 4/10 = 40%, still closed
    for _ <- 1..4, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # One more error: now [5 errors, 5 successes] = 50%, trips.
    RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)
  end