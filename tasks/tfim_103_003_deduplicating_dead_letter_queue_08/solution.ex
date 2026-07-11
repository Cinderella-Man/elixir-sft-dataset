  test "retry failure keeps entry and bumps retry_count (not occurrences)", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "k", :m, :err, %{})
    assert {:error, :boom} = DedupDLQ.retry(dlq, "q", "k", fn _ -> {:error, :boom} end)
    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
    assert e.occurrences == 1
  end