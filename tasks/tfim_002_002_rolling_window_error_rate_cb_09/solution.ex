  test "open → half_open after reset_timeout_ms", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    Clock.advance(1_000)
    assert :half_open = RollingRateCircuitBreaker.state(cb)
  end