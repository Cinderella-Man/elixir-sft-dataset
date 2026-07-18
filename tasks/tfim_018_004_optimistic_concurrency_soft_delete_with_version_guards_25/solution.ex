  test "soft delete of a deleted doc with a stale version reports stale first", %{srv: srv} do
    doc = create(srv)
    {:ok, _} = Documents.soft_delete_document(srv, doc.id, 0)

    assert {:error, :stale_version, 1} = Documents.soft_delete_document(srv, doc.id, 0)
  end