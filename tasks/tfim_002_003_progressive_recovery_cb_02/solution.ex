  test "passes through successes in closed state", %{cb: cb} do
    for _ <- 1..10, do: assert({:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn()))
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end