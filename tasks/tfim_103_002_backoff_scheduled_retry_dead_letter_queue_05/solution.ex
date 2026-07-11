  test "failure bumps retry_count and schedules exponential backoff", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})

    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
    assert e.next_retry_at == 1000

    Clock.advance(1000)
    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)
    assert [e2] = BackoffDLQ.peek(dlq, "q", 10)
    assert e2.retry_count == 2
    assert e2.next_retry_at == 3000
  end