  test "half_open admits no probe when half_open_max_probes is 0" do
    cb =
      start_cb(
        min_calls_in_window: 1,
        error_rate_threshold: 1.0,
        reset_timeout_ms: 1_000,
        half_open_max_probes: 0
      )

    assert {:error, :failure} = RollingRateCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)
    assert :half_open = RollingRateCircuitBreaker.state(cb)

    tracker = self()

    # In-flight probe count (0) is already at the maximum (0) → fail fast
    # without executing func, and the breaker stays half_open.
    assert {:error, :circuit_open} =
             RollingRateCircuitBreaker.call(cb, fn ->
               send(tracker, :probed)
               {:ok, :value}
             end)

    refute_received :probed
    assert :half_open = RollingRateCircuitBreaker.state(cb)
  end