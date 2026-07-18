  test "reset returns to closed from any state and clears the window", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    RollingRateCircuitBreaker.reset(cb)
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # Window should be empty — a new burst of errors shouldn't re-trip until
    # min_calls is met again.
    for _ <- 1..5, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end