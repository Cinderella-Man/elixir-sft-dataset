  test "raising handler counts as failure without crashing", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "k", :m, :err, %{})
    assert {:error, _} = DedupDLQ.retry(dlq, "q", "k", fn _ -> raise "x" end)
    assert Process.alive?(dlq)
    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
  end