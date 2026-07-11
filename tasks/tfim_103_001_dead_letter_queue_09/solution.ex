  test "retry with a failing handler keeps the message and increments retry_count", %{dlq: dlq} do
    {:ok, id} = DLQ.push(dlq, "q", :msg, :orig, %{})

    assert {:error, :boom} = DLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)

    assert [entry] = DLQ.peek(dlq, "q", 10)
    assert entry.id == id
    assert entry.retry_count == 1
  end