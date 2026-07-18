    test "restores with matching version", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id, 0)
      {:ok, res} = Documents.restore_document(srv, doc.id, del.lock_version)
      assert res.deleted_at == nil
      assert res.lock_version == 2
    end