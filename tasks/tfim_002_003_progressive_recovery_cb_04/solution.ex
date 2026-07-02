  test "success between failures resets consecutive failure count", %{cb: cb} do
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    # Non-consecutive — reset
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end