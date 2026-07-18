    test "no-op on already trashed", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id)
      {:ok, del2} = Documents.soft_delete_document(srv, doc.id)
      assert del2.deleted_at == del.deleted_at
    end