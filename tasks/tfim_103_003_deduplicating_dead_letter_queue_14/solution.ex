  test "queues are independent for the same dedup key", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "a", "k", :ma, :err, %{})
    {:ok, :new, _} = DedupDLQ.push(dlq, "b", "k", :mb, :err, %{})
    assert [ea] = DedupDLQ.peek(dlq, "a", 10)
    assert [eb] = DedupDLQ.peek(dlq, "b", 10)
    assert ea.message == :ma
    assert eb.message == :mb
  end