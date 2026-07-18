  test "base_backoff_ms defaults to 1000 when the option is omitted" do
    {:ok, dlq} = BackoffDLQ.start_link(clock: &Clock.now/0)
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})

    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.next_retry_at == 1000
    assert BackoffDLQ.ready(dlq, "q", 10) == []

    Clock.advance(999)
    assert {:error, :not_ready, 1} = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
    Clock.advance(1)
    assert [r] = BackoffDLQ.ready(dlq, "q", 10)
    assert r.id == id
  end