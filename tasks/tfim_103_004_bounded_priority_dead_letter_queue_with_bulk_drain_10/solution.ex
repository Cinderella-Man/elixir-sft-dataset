  test "purge removes by age", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :old, :err, %{}, :high)
    Clock.advance(1000)
    {:ok, b} = PriorityDLQ.push(dlq, "q", :new, :err, %{}, :low)

    assert {:ok, 1} = PriorityDLQ.purge(dlq, "q", 500)
    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.id == b
  end