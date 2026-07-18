  test "peek with a count of 0 returns [] without removing anything", %{dlq: dlq} do
    {:ok, id} = DLQ.push(dlq, "q", :kept, :err, %{})

    assert DLQ.peek(dlq, "q", 0) == []
    assert [entry] = DLQ.peek(dlq, "q", 1)
    assert entry.id == id
    assert entry.message == :kept
  end