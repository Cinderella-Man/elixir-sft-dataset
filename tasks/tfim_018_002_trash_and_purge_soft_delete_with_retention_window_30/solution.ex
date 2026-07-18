  test "soft_delete_document is a no-op on an expired document", %{srv: srv, advance: advance} do
    doc = create(srv)
    {:ok, del} = Documents.soft_delete_document(srv, doc.id)
    advance.(1000)

    assert {:ok, again} = Documents.soft_delete_document(srv, doc.id)
    assert again.deleted_at == del.deleted_at

    # the deadline must not be pushed forward: it stays expired, not restorable
    assert {:error, :expired} = Documents.restore_document(srv, doc.id)
    assert {:ok, 1} = Documents.purge_expired(srv)
  end