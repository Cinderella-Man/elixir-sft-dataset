  test "success removes the message", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :boom, %{})
    assert :ok = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
    assert BackoffDLQ.peek(dlq, "q", 10) == []
  end