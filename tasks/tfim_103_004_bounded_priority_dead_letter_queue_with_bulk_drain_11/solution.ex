  test "queues are independent", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "a", :ma, :err, %{}, :high)
    {:ok, _} = PriorityDLQ.push(dlq, "b", :mb, :err, %{}, :low)

    assert {:ok, %{succeeded: 1}} = PriorityDLQ.drain(dlq, "a", fn _ -> :ok end, 10)
    assert PriorityDLQ.peek(dlq, "a", 10) == []
    assert [%{message: :mb}] = PriorityDLQ.peek(dlq, "b", 10)
  end