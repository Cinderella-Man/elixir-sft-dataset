  test "push stores with priority and retry_count 0; peek returns it", %{dlq: dlq} do
    assert {:ok, id} = PriorityDLQ.push(dlq, "q", %{n: 1}, :timeout, %{s: "web"}, :normal)
    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.priority == :normal
    assert e.retry_count == 0
  end