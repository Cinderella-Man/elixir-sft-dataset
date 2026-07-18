  test "a throwing handler during drain counts as failure and keeps the entry", %{dlq: dlq} do
    {:ok, id} = PriorityDLQ.push(dlq, "q", :thrower, :err, %{}, :high)

    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", fn _ -> throw(:nope) end, 10)
    assert stats.succeeded == 0
    assert stats.failed == 1
    assert Process.alive?(dlq)

    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.retry_count == 1
  end