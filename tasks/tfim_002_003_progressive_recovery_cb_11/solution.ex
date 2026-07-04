  test "second failure in stage 1 exceeds tolerance → :open", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    # Clear stage 0
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Stage 1: 1 failure is fine, 2 is too many
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end