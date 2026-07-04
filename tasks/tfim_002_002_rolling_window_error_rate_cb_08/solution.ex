  test "open state rejects calls without executing the function", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    tracker = self()

    assert {:error, :circuit_open} =
             RollingRateCircuitBreaker.call(cb, fn ->
               send(tracker, :was_called)
               {:ok, :wat}
             end)

    refute_received :was_called
  end