  test "clears every recovery stage → :closed", %{cb: cb} do
    trip_to_half_open(cb)
    # Probe → recovering (stage 0)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 0: 3 calls, 0 failures tolerated
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 1: 5 calls, 1 failure tolerated
    for _ <- 1..5, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 2: 10 calls, 2 failures tolerated → final stage → :closed
    for _ <- 1..10, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end