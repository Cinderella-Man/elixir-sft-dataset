  test "retry success removes the coalesced entry", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "k", :m, :err, %{})
    assert :ok = DedupDLQ.retry(dlq, "q", "k", fn _ -> :ok end)
    assert DedupDLQ.peek(dlq, "q", 10) == []
  end