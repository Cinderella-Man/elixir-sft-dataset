  test "failure in stage 0 exceeds tolerance → :open", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Stage 0 tolerates 0 failures — a single error bounces back to :open
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end