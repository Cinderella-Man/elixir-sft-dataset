  test "does not trip when error rate is high but min_calls not met", %{cb: cb} do
    # 5 errors, 0 successes → 100% error rate, but only 5 calls (min = 6)
    for _ <- 1..5, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # 6th error now meets min_calls AND threshold → trip
    RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)
  end