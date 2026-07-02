  test "passes through successes without tripping", %{cb: cb} do
    for _ <- 1..20, do: assert({:ok, :value} = RollingRateCircuitBreaker.call(cb, ok_fn()))
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end