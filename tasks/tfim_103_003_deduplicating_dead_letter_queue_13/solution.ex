  test "duplicate push after a failed retry preserves retry_count", %{dlq: dlq} do
    {:ok, :new, id} = DedupDLQ.push(dlq, "q", "k", :first, :err_a, %{v: 1})
    assert {:error, :boom} = DedupDLQ.retry(dlq, "q", "k", fn _ -> {:error, :boom} end)

    Clock.advance(30)
    assert {:ok, :duplicate, ^id} = DedupDLQ.push(dlq, "q", "k", :second, :err_b, %{v: 2})

    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
    assert e.occurrences == 2
    assert e.id == id
    assert e.first_seen == 0
    assert e.last_seen == 30
    assert e.message == :second
  end