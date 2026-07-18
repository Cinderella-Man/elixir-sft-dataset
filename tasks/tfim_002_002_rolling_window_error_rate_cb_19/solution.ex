  test "call/2 on an expired open breaker performs the transition and runs a probe", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    # Timeout elapses but nobody calls state/1 — call/2 itself must flip and probe.
    Clock.advance(1_000)
    tracker = self()

    assert {:ok, :probed} =
             RollingRateCircuitBreaker.call(cb, fn ->
               send(tracker, :probe_ran)
               {:ok, :probed}
             end)

    assert_received :probe_ran
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end