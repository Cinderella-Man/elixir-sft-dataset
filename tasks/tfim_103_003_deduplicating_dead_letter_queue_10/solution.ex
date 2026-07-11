  test "retry on unknown dedup key returns :not_found", %{dlq: dlq} do
    assert {:error, :not_found} = DedupDLQ.retry(dlq, "q", "nope", fn _ -> :ok end)
  end