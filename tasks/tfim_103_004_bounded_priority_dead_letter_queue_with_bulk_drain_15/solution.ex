  test "purge removes entries whose age is exactly older_than", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :exact, :err, %{}, :high)
    Clock.advance(500)
    {:ok, younger} = PriorityDLQ.push(dlq, "q", :younger, :err, %{}, :low)

    assert {:ok, 1} = PriorityDLQ.purge(dlq, "q", 500)
    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.id == younger
  end