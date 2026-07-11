  test "retry on unknown id returns :not_found", %{dlq: dlq} do
    assert {:error, :not_found} = BackoffDLQ.retry(dlq, "q", 999, fn _ -> :ok end)
    assert {:error, :not_found} = BackoffDLQ.retry(dlq, "missing", 0, fn _ -> :ok end)
  end