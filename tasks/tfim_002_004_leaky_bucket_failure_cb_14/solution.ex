  test "open state rejects calls without executing", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())

    tracker = self()

    assert {:error, :circuit_open} =
             LeakyBucketCircuitBreaker.call(cb, fn ->
               send(tracker, :was_called)
               {:ok, :v}
             end)

    refute_received :was_called
  end