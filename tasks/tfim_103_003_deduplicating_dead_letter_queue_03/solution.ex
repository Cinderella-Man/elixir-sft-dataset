  test "peek on unknown queue returns []", %{dlq: dlq} do
    assert DedupDLQ.peek(dlq, "nope", 10) == []
  end