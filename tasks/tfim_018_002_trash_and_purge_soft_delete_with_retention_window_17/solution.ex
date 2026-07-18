    test "sets deleted_at", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id)
      assert del.deleted_at != nil
    end