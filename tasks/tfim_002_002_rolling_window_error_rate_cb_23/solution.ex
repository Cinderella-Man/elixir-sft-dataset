  test "state on a half_open breaker never consumes the sole probe slot", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)

    # Repeated state/1 in half_open must not use up the single probe slot.
    assert :half_open = RollingRateCircuitBreaker.state(cb)
    assert :half_open = RollingRateCircuitBreaker.state(cb)
    assert :half_open = RollingRateCircuitBreaker.state(cb)

    tracker = self()

    assert {:ok, :ran} =
             RollingRateCircuitBreaker.call(cb, fn ->
               send(tracker, :probe_ran)
               {:ok, :ran}
             end)

    assert_received :probe_ran
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end