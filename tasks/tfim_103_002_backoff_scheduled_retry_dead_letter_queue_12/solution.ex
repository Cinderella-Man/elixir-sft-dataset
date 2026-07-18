  test "queues are independent", %{dlq: dlq} do
    {:ok, a} = BackoffDLQ.push(dlq, "a", :ma, :err, %{})
    {:ok, _} = BackoffDLQ.push(dlq, "b", :mb, :err, %{})

    assert {:error, :x} = BackoffDLQ.retry(dlq, "a", a, fn _ -> {:error, :x} end)
    assert [ea] = BackoffDLQ.peek(dlq, "a", 10)
    assert ea.retry_count == 1
    assert [eb] = BackoffDLQ.peek(dlq, "b", 10)
    assert eb.retry_count == 0
  end