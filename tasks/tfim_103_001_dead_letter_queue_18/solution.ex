  test "retry with a handler returning an unexpected value fails and keeps the message", %{
    dlq: dlq
  } do
    {:ok, id} = DLQ.push(dlq, "q", :msg, :orig, %{})

    assert {:error, _reason} = DLQ.retry(dlq, "q", id, fn _ -> :weird end)
    assert Process.alive?(dlq)

    assert [entry] = DLQ.peek(dlq, "q", 10)
    assert entry.id == id
    assert entry.message == :msg
    assert entry.retry_count == 1

    assert {:error, _other} = DLQ.retry(dlq, "q", id, fn _ -> {:not, :ok} end)
    assert [entry2] = DLQ.peek(dlq, "q", 10)
    assert entry2.retry_count == 2
  end