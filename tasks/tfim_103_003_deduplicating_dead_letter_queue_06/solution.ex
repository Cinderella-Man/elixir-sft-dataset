  test "peek orders oldest-first by first_seen", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "a", :first, :err, %{})
    Clock.advance(1)
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "b", :second, :err, %{})
    # re-push "a" as duplicate — must NOT reorder it to the back
    Clock.advance(1)
    {:ok, :duplicate, _} = DedupDLQ.push(dlq, "q", "a", :first, :err, %{})

    assert Enum.map(DedupDLQ.peek(dlq, "q", 10), & &1.dedup_key) == ["a", "b"]
  end