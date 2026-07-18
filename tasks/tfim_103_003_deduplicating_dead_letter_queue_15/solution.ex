  test "retry handler returning {:ok, term} succeeds and removes the entry", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "k", :m, :err, %{})
    assert :ok = DedupDLQ.retry(dlq, "q", "k", fn :m -> {:ok, :done} end)
    assert DedupDLQ.peek(dlq, "q", 10) == []
  end