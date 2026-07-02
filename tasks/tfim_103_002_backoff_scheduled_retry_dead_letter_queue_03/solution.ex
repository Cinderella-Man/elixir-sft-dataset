  test "peek on unknown queue returns []", %{dlq: dlq} do
    assert BackoffDLQ.peek(dlq, "nope", 10) == []
  end