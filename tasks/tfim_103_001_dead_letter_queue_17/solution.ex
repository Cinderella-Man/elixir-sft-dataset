  test "purge is scoped to a single queue", %{dlq: dlq} do
    {:ok, _} = DLQ.push(dlq, "a", :ma, :err, %{})
    {:ok, _} = DLQ.push(dlq, "b", :mb, :err, %{})

    Clock.advance(5_000)
    assert {:ok, 1} = DLQ.purge(dlq, "a", 1_000)

    assert DLQ.peek(dlq, "a", 10) == []
    assert [%{message: :mb}] = DLQ.peek(dlq, "b", 10)
  end