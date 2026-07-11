  test "retry before next_retry_at is rejected as :not_ready without running the handler", %{
    dlq: dlq
  } do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})
    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)

    # now still 0, next_retry_at == 1000
    assert {:error, :not_ready, 1000} = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
    # unchanged retry_count proves the handler did not run
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
  end