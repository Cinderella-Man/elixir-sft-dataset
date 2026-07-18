  test "raised exception in :recovering counts as a stage failure", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    # Stage 0: zero tolerance

    assert {:error, %RuntimeError{}} =
             ProgressiveRecoveryCircuitBreaker.call(cb, fn -> raise "boom" end)

    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end