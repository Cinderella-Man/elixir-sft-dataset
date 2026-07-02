  test "peek on unknown queue returns []", %{dlq: dlq} do
    assert PriorityDLQ.peek(dlq, "nope", 10) == []
  end