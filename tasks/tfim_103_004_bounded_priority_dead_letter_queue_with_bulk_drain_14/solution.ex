  test "drain treats an unexpected handler return as failure and keeps the entry", %{dlq: dlq} do
    {:ok, id} = PriorityDLQ.push(dlq, "q", :m1, :err, %{}, :normal)

    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", fn _ -> :something_else end, 10)
    assert stats.succeeded == 0
    assert stats.failed == 1
    assert stats.processed == [id]

    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.retry_count == 1
  end