  test "probe failure → :open with restarted reset timeout", %{cb: cb} do
    trip_to_half_open(cb)

    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Reset timer restarts from the new :open transition, not from original
    Clock.advance(500)
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
    Clock.advance(500)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end