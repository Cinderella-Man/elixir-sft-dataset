  test "reset returns to :closed from :recovering and clears stage counters", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    # Advance into stage 1 with some progress
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    ProgressiveRecoveryCircuitBreaker.reset(cb)
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)

    # After reset, failure count should be fresh — need full 3 consecutive
    # failures to trip again (not some leftover count).
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end