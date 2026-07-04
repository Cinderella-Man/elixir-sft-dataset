  test "half_open probe success → closed with empty window", %{cb: cb} do
    # Trip, then wait to half-open
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)
    assert :half_open = RollingRateCircuitBreaker.state(cb)

    # Successful probe → closed
    assert {:ok, :value} = RollingRateCircuitBreaker.call(cb, ok_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # Old outcomes are wiped — 3 fresh errors shouldn't trip (below min_calls)
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end