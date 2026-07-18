  test "default ladder: stage 0 needs 5 calls, stage 1 needs 15 with 1 failure tolerated" do
    cb = default_cb_in_recovering()

    # 4 of the 5 calls required by stage 0 — stage not cleared yet.
    repeat_call(cb, 4, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # 5th call clears stage 0 → stage 1 ({15, 1}).
    assert {:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 1 tolerates exactly 1 failure (a stage-0 zero tolerance here
    # would have reopened the circuit).
    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # 1 failure + 13 successes = 14 of the 15 calls stage 1 requires.
    repeat_call(cb, 13, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # The 15th call is a 2nd failure → exceeds stage 1 tolerance → :open.
    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end