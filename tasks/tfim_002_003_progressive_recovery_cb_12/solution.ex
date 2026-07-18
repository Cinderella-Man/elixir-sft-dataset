  test "reopening from :recovering restarts reset timeout", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Trigger recovery failure → :open
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Reset timer must be fresh (1s), not carried over
    Clock.advance(500)
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
    Clock.advance(500)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end