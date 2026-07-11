  test "a raising handler during drain does not crash the process", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :boom, :err, %{}, :high)
    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", fn _ -> raise "x" end, 10)
    assert stats.failed == 1
    assert Process.alive?(dlq)
    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
  end