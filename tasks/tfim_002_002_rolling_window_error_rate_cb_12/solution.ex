  test "raised exceptions count as failures and don't crash the GenServer", %{cb: cb} do
    raise_fn = fn -> raise "boom" end

    assert {:error, %RuntimeError{message: "boom"}} =
             RollingRateCircuitBreaker.call(cb, raise_fn)

    pid = Process.whereis(cb)
    assert Process.alive?(pid)

    # 6 raises should meet min_calls at 100% error rate → trip
    for _ <- 1..5, do: RollingRateCircuitBreaker.call(cb, raise_fn)
    assert :open = RollingRateCircuitBreaker.state(cb)
  end