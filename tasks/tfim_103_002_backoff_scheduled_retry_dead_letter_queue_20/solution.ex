  test "purge removes an entry whose age exactly equals older_than", %{dlq: dlq} do
    {:ok, _a} = BackoffDLQ.push(dlq, "q", :exact, :err, %{})
    Clock.advance(400)
    {:ok, b} = BackoffDLQ.push(dlq, "q", :younger, :err, %{})
    Clock.advance(100)

    # a is exactly 500ms old (>= 500 → purged), b is 100ms old (< 500 → kept)
    assert {:ok, 1} = BackoffDLQ.purge(dlq, "q", 500)
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.id == b

    # an unknown queue purges nothing
    assert {:ok, 0} = BackoffDLQ.purge(dlq, "nope", 0)
  end