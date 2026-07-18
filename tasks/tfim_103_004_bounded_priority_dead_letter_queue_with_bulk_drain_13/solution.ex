  test "drain treats {:ok, term} as success and removes the entry", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :m1, :err, %{}, :high)

    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", fn _ -> {:ok, :handled} end, 10)
    assert stats.succeeded == 1
    assert stats.failed == 0
    assert PriorityDLQ.peek(dlq, "q", 10) == []
  end