  test "repeated key coalesces: same id, bumped occurrences, latest data, refreshed last_seen", %{dlq: dlq} do
    {:ok, :new, id} = DedupDLQ.push(dlq, "q", "k", :first, :err_a, %{v: 1})
    Clock.advance(100)
    assert {:ok, :duplicate, ^id} = DedupDLQ.push(dlq, "q", "k", :second, :err_b, %{v: 2})

    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.occurrences == 2
    assert e.message == :second
    assert e.error_reason == :err_b
    assert e.metadata == %{v: 2}
    assert e.first_seen == 0
    assert e.last_seen == 100
  end