  test "default failure_threshold trips only on the 5th consecutive failure" do
    cb = start_cb([])

    repeat_call(cb, 4, err_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)

    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end