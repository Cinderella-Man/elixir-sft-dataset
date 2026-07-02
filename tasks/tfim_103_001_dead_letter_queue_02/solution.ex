  test "push stores a message and peek returns it with retry_count 0", %{dlq: dlq} do
    assert {:ok, id} = DLQ.push(dlq, "orders", %{n: 1}, :timeout, %{source: "web"})
    assert is_binary(id) or is_reference(id) or is_integer(id)

    assert [entry] = DLQ.peek(dlq, "orders", 10)
    assert entry.id == id
    assert entry.message == %{n: 1}
    assert entry.error_reason == :timeout
    assert entry.metadata == %{source: "web"}
    assert entry.retry_count == 0
  end