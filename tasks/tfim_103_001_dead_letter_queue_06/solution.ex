  test "retry with a succeeding handler (:ok) removes the message", %{dlq: dlq} do
    {:ok, id} = DLQ.push(dlq, "q", %{payload: 42}, :boom, %{})

    test_pid = self()

    handler = fn msg ->
      send(test_pid, {:handled, msg})
      :ok
    end

    assert :ok = DLQ.retry(dlq, "q", id, handler)
    assert_received {:handled, %{payload: 42}}
    assert DLQ.peek(dlq, "q", 10) == []
  end