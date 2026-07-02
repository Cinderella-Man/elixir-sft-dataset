  test "trips on threshold consecutive failures", %{cb: cb} do
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end