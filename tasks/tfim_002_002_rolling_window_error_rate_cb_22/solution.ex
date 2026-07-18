  test "reset on a closed breaker discards accumulated window failures", %{cb: cb} do
    # 5 errors: below min_calls (6), so still closed but the window is dirty.
    for _ <- 1..5, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    assert :ok = RollingRateCircuitBreaker.reset(cb)

    # Had reset been a no-op, 5 + 5 = 10 errors at 100% would have tripped.
    for _ <- 1..5, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end