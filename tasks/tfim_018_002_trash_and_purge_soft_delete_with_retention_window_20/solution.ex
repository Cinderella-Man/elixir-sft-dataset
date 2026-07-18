    test "restores a trashed document within window", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      {:ok, restored} = Documents.restore_document(srv, doc.id)
      assert restored.deleted_at == nil
    end