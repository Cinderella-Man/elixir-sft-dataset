  test "purge is based on last_seen; a recent duplicate protects the entry", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "stale", :m, :err, %{})
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "fresh", :m, :err, %{})

    Clock.advance(100)
    # refresh "fresh" so its last_seen is recent
    {:ok, :duplicate, _} = DedupDLQ.push(dlq, "q", "fresh", :m, :err, %{})

    Clock.advance(20)
    # now = 120: "stale" last_seen 0 (age 120 >= 50 -> purged),
    #            "fresh" last_seen 100 (age 20 < 50 -> kept)
    assert {:ok, 1} = DedupDLQ.purge(dlq, "q", 50)
    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.dedup_key == "fresh"
  end