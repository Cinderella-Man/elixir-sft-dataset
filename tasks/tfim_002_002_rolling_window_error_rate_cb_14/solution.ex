  test "defaults: 10 min_calls, 30_000 ms reset timeout, one half_open probe" do
    cb = start_cb([])

    # Default min_calls_in_window is 10: nine 100%-error calls are not enough
    # evidence, the tenth exactly meets the (inclusive) floor at rate 1.0 ≥ 0.5.
    for _ <- 1..9, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    assert {:error, :failure} = RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    # Default reset_timeout_ms is 30_000, boundary inclusive.
    Clock.advance(29_999)
    assert :open = RollingRateCircuitBreaker.state(cb)

    Clock.advance(1)
    assert :half_open = RollingRateCircuitBreaker.state(cb)

    # Default half_open_max_probes is 1: exactly one probe is admitted and a
    # successful probe closes the breaker.
    assert {:ok, :value} = RollingRateCircuitBreaker.call(cb, ok_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end