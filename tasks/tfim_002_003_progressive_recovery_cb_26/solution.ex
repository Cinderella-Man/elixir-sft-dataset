  test "re-probe after reopening from a later stage restarts recovery at stage 0", %{cb: cb} do
    trip_to_half_open(cb)
    # Probe success → recovering stage 0.
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Clear stage 0 {3, 0} → now in stage 1 {5, 1}.
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Exceed stage 1 tolerance (2 failures) → :open, from a deep stage.
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Back to half-open; a fresh probe success must restart recovery at stage 0.
    Clock.advance(1_000)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 0 tolerates zero failures — a single failure reopens. If recovery
    # had resumed at stage 1 (tolerates 1), this failure would be tolerated.
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end