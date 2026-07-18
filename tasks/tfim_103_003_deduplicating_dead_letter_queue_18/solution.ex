  test "throwing handler counts as failure without crashing", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "k", :m, :err, %{})
    assert {:error, _} = DedupDLQ.retry(dlq, "q", "k", fn _ -> throw(:nope) end)
    assert Process.alive?(dlq)
    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
    # the process still serves subsequent calls
    assert :ok = DedupDLQ.retry(dlq, "q", "k", fn _ -> :ok end)
  end