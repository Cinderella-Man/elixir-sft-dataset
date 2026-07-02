  test "peek on an unknown or empty queue returns []", %{dlq: dlq} do
    assert DLQ.peek(dlq, "nope", 10) == []
  end