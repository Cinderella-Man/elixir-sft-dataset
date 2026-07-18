  test "purge removes an entry whose age exactly equals older_than", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "edge", :m, :err, %{})
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "young", :m, :err, %{})
    Clock.advance(49)
    {:ok, :duplicate, _} = DedupDLQ.push(dlq, "q", "young", :m, :err, %{})

    Clock.advance(1)
    # now = 50: "edge" age 50 >= 50 -> purged, "young" age 1 < 50 -> kept
    assert {:ok, 1} = DedupDLQ.purge(dlq, "q", 50)
    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.dedup_key == "young"
  end