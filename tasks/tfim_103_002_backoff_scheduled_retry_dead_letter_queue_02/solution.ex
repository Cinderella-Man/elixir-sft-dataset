  test "push stores a pending, immediately-ready message", %{dlq: dlq} do
    assert {:ok, id} = BackoffDLQ.push(dlq, "q", %{n: 1}, :timeout, %{src: "web"})
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.retry_count == 0
    assert e.status == :pending
    assert e.next_retry_at == 0
    assert [r] = BackoffDLQ.ready(dlq, "q", 10)
    assert r.id == id
  end