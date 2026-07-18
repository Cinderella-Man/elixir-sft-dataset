  test "closing via full recovery leaves a zeroed consecutive failure count" do
    cb = default_cb_in_recovering()

    repeat_call(cb, 5, ok_fn())
    repeat_call(cb, 15, ok_fn())
    repeat_call(cb, 30, ok_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)

    # A full 5 consecutive failures must be needed again, not fewer.
    repeat_call(cb, 4, err_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)

    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end