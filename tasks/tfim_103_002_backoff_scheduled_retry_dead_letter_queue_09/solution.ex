  test "a raising handler counts as failure and does not crash the process", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})
    assert {:error, _} = BackoffDLQ.retry(dlq, "q", id, fn _ -> raise "kaboom" end)
    assert Process.alive?(dlq)
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
  end