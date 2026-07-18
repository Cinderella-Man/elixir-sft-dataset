  test "retry does not find a message id that lives in a different queue", %{dlq: dlq} do
    {:ok, a_id} = DLQ.push(dlq, "a", :ma, :err, %{})
    {:ok, _b_id} = DLQ.push(dlq, "b", :mb, :err, %{})

    test_pid = self()
    handler = fn msg -> send(test_pid, {:called, msg}) && :ok end

    assert {:error, :not_found} = DLQ.retry(dlq, "b", a_id, handler)
    refute_received {:called, _}

    assert [%{id: ^a_id, retry_count: 0, message: :ma}] = DLQ.peek(dlq, "a", 10)
    assert [%{message: :mb, retry_count: 0}] = DLQ.peek(dlq, "b", 10)
  end