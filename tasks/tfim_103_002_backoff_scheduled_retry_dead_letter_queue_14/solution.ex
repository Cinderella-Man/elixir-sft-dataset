  test "peek returns at most count entries, oldest-first", %{dlq: dlq} do
    {:ok, a} = BackoffDLQ.push(dlq, "q", :first, :err, %{})
    Clock.advance(10)
    {:ok, b} = BackoffDLQ.push(dlq, "q", :second, :err, %{})
    Clock.advance(10)
    {:ok, c} = BackoffDLQ.push(dlq, "q", :third, :err, %{})

    # count caps the result and the oldest push comes first
    assert [e1, e2] = BackoffDLQ.peek(dlq, "q", 2)
    assert e1.id == a
    assert e1.message == :first
    assert e2.id == b
    assert e2.message == :second

    # a count larger than the queue yields every entry, still oldest-first
    assert Enum.map(BackoffDLQ.peek(dlq, "q", 10), & &1.id) == [a, b, c]
  end