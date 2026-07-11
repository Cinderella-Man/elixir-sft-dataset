  test "retry only removes the retried message, others remain", %{dlq: dlq} do
    {:ok, id1} = DLQ.push(dlq, "q", :one, :err, %{})
    {:ok, _id2} = DLQ.push(dlq, "q", :two, :err, %{})

    assert :ok = DLQ.retry(dlq, "q", id1, fn _ -> :ok end)

    remaining = DLQ.peek(dlq, "q", 10)
    assert Enum.map(remaining, & &1.message) == [:two]
  end