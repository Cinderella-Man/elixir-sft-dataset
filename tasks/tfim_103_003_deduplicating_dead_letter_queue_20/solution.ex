  test "server can be registered under a name and driven through it" do
    {:ok, _} = DedupDLQ.start_link(name: :dedup_dlq_named_server, clock: &Clock.now/0)

    assert {:ok, :new, id} =
             DedupDLQ.push(:dedup_dlq_named_server, "q", "k", :m, :err, %{})

    assert {:ok, :duplicate, ^id} =
             DedupDLQ.push(:dedup_dlq_named_server, "q", "k", :m2, :err, %{})

    assert [e] = DedupDLQ.peek(:dedup_dlq_named_server, "q", 10)
    assert e.occurrences == 2
    assert :ok = DedupDLQ.retry(:dedup_dlq_named_server, "q", "k", fn _ -> :ok end)
    assert DedupDLQ.peek(:dedup_dlq_named_server, "q", 10) == []
  end