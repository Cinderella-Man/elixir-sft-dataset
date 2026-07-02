  test "trips when error rate reaches threshold and min calls are met", %{cb: cb} do
    # Window: [:ok, :ok, :ok, :error, :error, :error] → 3/6 = 50% ≥ 0.5
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())

    assert :open = RollingRateCircuitBreaker.state(cb)
  end