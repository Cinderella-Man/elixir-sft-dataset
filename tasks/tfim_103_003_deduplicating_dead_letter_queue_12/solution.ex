  test "peek truncates to count, keeping the oldest entries", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "a", :ma, :err, %{})
    Clock.advance(1)
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "b", :mb, :err, %{})
    Clock.advance(1)
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "c", :mc, :err, %{})

    assert Enum.map(DedupDLQ.peek(dlq, "q", 2), & &1.dedup_key) == ["a", "b"]
    assert Enum.map(DedupDLQ.peek(dlq, "q", 1), & &1.dedup_key) == ["a"]
    assert DedupDLQ.peek(dlq, "q", 0) == []
    # peeking is non-destructive: all three are still queued
    assert length(DedupDLQ.peek(dlq, "q", 3)) == 3
  end