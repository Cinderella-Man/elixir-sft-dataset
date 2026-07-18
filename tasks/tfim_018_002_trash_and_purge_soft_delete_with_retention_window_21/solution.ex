    test "no-op restoring an active document", %{srv: srv} do
      doc = create(srv)
      assert {:ok, got} = Documents.restore_document(srv, doc.id)
      assert got.deleted_at == nil
    end