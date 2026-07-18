  test "stage failure counter resets when advancing to the next stage", %{cb: cb} do
    trip_to_half_open(cb)
    # Probe success → recovering stage 0.
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Clear stage 0 {3, 0}: three clean successes → advance to stage 1.
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 1 {5, 1}: one tolerated failure then four successes → 5 calls → stage 2.
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    for _ <- 1..4, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 2 {10, 2}: two failures must be tolerated afresh. If the stage-1
    # failure carried over, 1 + 2 = 3 > 2 would reopen the circuit.
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)
  end