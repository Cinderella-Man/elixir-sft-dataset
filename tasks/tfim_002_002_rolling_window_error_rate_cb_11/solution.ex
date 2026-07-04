  test "half_open probe failure → open and restarts reset timeout", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)
    assert :half_open = RollingRateCircuitBreaker.state(cb)

    assert {:error, :failure} = RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    # Reset timeout must restart, not carry over
    Clock.advance(500)
    assert :open = RollingRateCircuitBreaker.state(cb)

    Clock.advance(500)
    assert :half_open = RollingRateCircuitBreaker.state(cb)
  end