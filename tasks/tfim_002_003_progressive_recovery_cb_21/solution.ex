  test "default final stage needs 30 calls and tolerates 2 failures before closing" do
    cb = default_cb_in_recovering()

    repeat_call(cb, 5, ok_fn())
    repeat_call(cb, 15, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 2 ({30, 2}): two failures are within tolerance.
    repeat_call(cb, 2, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # 2 failures + 27 successes = 29 of the 30 required calls — not closed yet.
    repeat_call(cb, 27, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # The 30th call clears the final stage → :closed.
    assert {:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end