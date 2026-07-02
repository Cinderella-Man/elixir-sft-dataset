  test "does not trip when error rate is below threshold", %{cb: cb} do
    # 3 errors out of 10 = 30%, below 50% threshold
    for _ <- 1..7, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())

    assert :closed = RollingRateCircuitBreaker.state(cb)
  end