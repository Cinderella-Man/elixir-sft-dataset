  test "purge removes by age regardless of status", %{dlq: dlq} do
    {:ok, _} = BackoffDLQ.push(dlq, "q", :old, :err, %{})
    Clock.advance(1000)
    {:ok, b} = BackoffDLQ.push(dlq, "q", :new, :err, %{})

    assert {:ok, 1} = BackoffDLQ.purge(dlq, "q", 500)
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.id == b
  end