  test "retry treats {:ok, term} as success and removes the message", %{dlq: dlq} do
    {:ok, id} = DLQ.push(dlq, "q", :msg, :boom, %{})
    assert :ok = DLQ.retry(dlq, "q", id, fn _ -> {:ok, :done} end)
    assert DLQ.peek(dlq, "q", 10) == []
  end