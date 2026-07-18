  test "half-open lets no calls through when the probe budget is zero" do
    cb =
      start_cb(
        failure_threshold: 3,
        reset_timeout_ms: 1_000,
        half_open_max_probes: 0,
        recovery_stages: [{3, 0}]
      )

    repeat_call(cb, 3, err_fn())
    Clock.advance(1_000)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)

    tracker = self()

    assert {:error, :circuit_open} =
             ProgressiveRecoveryCircuitBreaker.call(cb, fn ->
               send(tracker, :was_called)
               {:ok, :v}
             end)

    refute_received :was_called
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end