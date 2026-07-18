  test "handler returning a non-ok, non-error value counts as a failure", %{dlq: dlq} do
    {:ok, :new, id} = DedupDLQ.push(dlq, "q", "k", :m, :err, %{})
    assert {:error, _reason} = DedupDLQ.retry(dlq, "q", "k", fn _ -> :weird end)
    assert Process.alive?(dlq)
    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.retry_count == 1
    assert e.occurrences == 1
  end