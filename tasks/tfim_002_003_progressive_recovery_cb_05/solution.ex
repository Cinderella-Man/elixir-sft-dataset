  test "open state rejects calls without executing", %{cb: cb} do
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())

    tracker = self()

    assert {:error, :circuit_open} =
             ProgressiveRecoveryCircuitBreaker.call(cb, fn ->
               send(tracker, :was_called)
               {:ok, :v}
             end)

    refute_received :was_called
  end