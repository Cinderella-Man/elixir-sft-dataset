  test "default retention_ms keeps a trashed doc restorable until 30 days have elapsed" do
    {:ok, clock} = Agent.start_link(fn -> 0 end)
    now = fn -> Agent.get(clock, & &1) end
    {:ok, srv} = Documents.start_link(clock: now)
    {:ok, doc} = Documents.create_document(srv, %{title: "T", content: "C"})
    {:ok, _} = Documents.soft_delete_document(srv, doc.id)

    thirty_days = 30 * 24 * 60 * 60 * 1000
    Agent.update(clock, fn _ -> thirty_days - 1 end)
    assert {:ok, restored} = Documents.restore_document(srv, doc.id)
    assert restored.deleted_at == nil

    {:ok, _} = Documents.soft_delete_document(srv, doc.id)
    Agent.update(clock, fn t -> t + thirty_days end)
    assert {:error, :expired} = Documents.restore_document(srv, doc.id)
  end