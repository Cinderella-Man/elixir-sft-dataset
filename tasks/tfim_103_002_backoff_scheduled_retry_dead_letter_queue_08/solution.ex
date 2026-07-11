  test "message becomes :dead after max_attempts failures and is no longer retryable", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})

    fail = fn _ -> {:error, :again} end
    # rc 1, due 1000
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    Clock.advance(1000)
    # rc 2, due 3000
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    Clock.advance(2000)
    # rc 3 -> dead
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)

    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.status == :dead
    assert e.retry_count == 3

    assert {:error, :dead} = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
    assert BackoffDLQ.ready(dlq, "q", 10) == []
  end