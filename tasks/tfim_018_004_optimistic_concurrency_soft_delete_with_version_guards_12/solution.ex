    test "deletes with matching version", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id, 0)
      assert del.deleted_at != nil
      assert del.lock_version == 1
    end