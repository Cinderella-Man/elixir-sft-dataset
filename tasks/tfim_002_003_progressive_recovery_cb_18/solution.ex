  test "default reset timeout is 30_000ms and the default single probe is allowed" do
    cb = start_cb([])
    repeat_call(cb, 5, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    Clock.advance(29_999)
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    Clock.advance(1)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)

    # half_open_max_probes defaults to 1 — the probe must be let through.
    assert {:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)
  end