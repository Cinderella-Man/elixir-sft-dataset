  test "retry on an unknown message id returns {:error, :not_found}", %{dlq: dlq} do
    assert {:error, :not_found} = DLQ.retry(dlq, "q", "no-such-id", fn _ -> :ok end)

    assert {:error, :not_found} =
             DLQ.retry(dlq, "missing-queue", "x", fn _ -> :ok end)
  end