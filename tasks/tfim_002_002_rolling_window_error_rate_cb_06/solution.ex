  test "alternating success/failure trips once threshold is met", %{cb: cb} do
    # Strict 50/50 alternation — would never trip a consecutive-count breaker.
    for _ <- 1..3 do
      RollingRateCircuitBreaker.call(cb, ok_fn())
      RollingRateCircuitBreaker.call(cb, err_fn())
    end

    # Window: 3 errors / 6 total = 50% ≥ 0.5, min_calls met → trip
    assert :open = RollingRateCircuitBreaker.state(cb)
  end