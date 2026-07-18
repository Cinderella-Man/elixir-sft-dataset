  test "reset returns to :closed from :open", %{cb: cb} do
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    ProgressiveRecoveryCircuitBreaker.reset(cb)
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end