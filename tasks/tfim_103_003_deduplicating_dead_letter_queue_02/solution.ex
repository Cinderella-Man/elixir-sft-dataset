  test "first push creates a new entry with occurrences 1", %{dlq: dlq} do
    assert {:ok, :new, id} = DedupDLQ.push(dlq, "orders", "k1", %{n: 1}, :timeout, %{src: "web"})
    assert [e] = DedupDLQ.peek(dlq, "orders", 10)
    assert e.id == id
    assert e.dedup_key == "k1"
    assert e.occurrences == 1
    assert e.retry_count == 0
    assert e.first_seen == 0
    assert e.last_seen == 0
  end