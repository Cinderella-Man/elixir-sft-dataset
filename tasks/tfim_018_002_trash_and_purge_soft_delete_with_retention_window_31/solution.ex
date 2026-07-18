  test "document one millisecond short of the retention window is still restorable",
       %{srv: srv, advance: advance} do
    doc = create(srv)
    {:ok, _} = Documents.soft_delete_document(srv, doc.id)
    advance.(999)

    assert {:ok, 0} = Documents.purge_expired(srv)
    assert {:ok, restored} = Documents.restore_document(srv, doc.id)
    assert restored.deleted_at == nil
    assert {:ok, _} = Documents.get_document(srv, doc.id)
  end