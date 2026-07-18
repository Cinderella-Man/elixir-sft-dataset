  test "unexpected return values are wrapped and counted as failures", %{cb: cb} do
    assert {:error, {:unexpected_return, :ok}} =
             RollingRateCircuitBreaker.call(cb, fn -> :ok end)

    assert {:error, {:unexpected_return, 42}} = RollingRateCircuitBreaker.call(cb, fn -> 42 end)

    # Six failures at a 100% rate meet min_calls (6) and the 0.5 threshold.
    for _ <- 1..4, do: RollingRateCircuitBreaker.call(cb, fn -> nil end)
    assert :open = RollingRateCircuitBreaker.state(cb)
  end