  test "an unexpected return shape counts as a failure in closed state" do
    cb =
      start_cb(
        failure_threshold: 3,
        reset_timeout_ms: 1_000,
        recovery_stages: [{3, 0}]
      )

    repeat_call(cb, 2, fn -> :not_a_result end)
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)

    ProgressiveRecoveryCircuitBreaker.call(cb, fn -> :not_a_result end)
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end