  test "failure within stage tolerance stays in stage", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Clear stage 0 (3 calls, 0 failures)
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Now in stage 1: 5 calls, 1 failure tolerated
    # 2 successes + 1 failure = stage_calls=3, stage_failures=1, still under limit
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # 2 more successes: stage_calls=5, advance to stage 2
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)
  end