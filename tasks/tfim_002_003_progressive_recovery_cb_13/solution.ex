  test "raised exception is a failure and doesn't crash the GenServer", %{cb: cb} do
    raise_fn = fn -> raise "boom" end

    assert {:error, %RuntimeError{message: "boom"}} =
             ProgressiveRecoveryCircuitBreaker.call(cb, raise_fn)

    pid = Process.whereis(cb)
    assert Process.alive?(pid)

    # 2 more raises (threshold=3) → trip
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, raise_fn)
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end