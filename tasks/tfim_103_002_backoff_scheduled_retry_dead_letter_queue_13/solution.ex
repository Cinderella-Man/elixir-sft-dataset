  test "a handler returning {:ok, term} is a success that removes the message", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :boom, %{})

    # {:ok, term} is a success: :ok is returned, nothing is left behind, and no
    # retry was counted or backoff scheduled (which a failure classification would do).
    assert :ok = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:ok, :delivered} end)
    assert BackoffDLQ.peek(dlq, "q", 10) == []
    assert BackoffDLQ.ready(dlq, "q", 10) == []
    assert {:error, :not_found} = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
  end