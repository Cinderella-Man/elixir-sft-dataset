  test "purge_document hard-deletes an expired document", %{srv: srv, advance: advance} do
    doc = create(srv, %{title: "gone"})
    {:ok, _} = Documents.soft_delete_document(srv, doc.id)
    advance.(1000)
    assert {:error, :expired} = Documents.restore_document(srv, doc.id)

    assert {:ok, purged} = Documents.purge_document(srv, doc.id)
    assert purged.id == doc.id
    assert {:error, :not_found} = Documents.get_document(srv, doc.id, include_deleted: true)
    assert {:ok, 0} = Documents.purge_expired(srv)
  end