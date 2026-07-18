  test "a handler returning an unrecognised term is a failure that backs off", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})

    assert {:error, _} = BackoffDLQ.retry(dlq, "q", id, fn _ -> :something_else end)
    assert Process.alive?(dlq)

    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
    assert e.status == :pending
    assert e.next_retry_at == 1000
    assert BackoffDLQ.ready(dlq, "q", 10) == []
  end