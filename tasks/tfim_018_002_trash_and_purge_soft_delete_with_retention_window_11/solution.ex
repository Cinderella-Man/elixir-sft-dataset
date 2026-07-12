    test "trashed hidden by default, visible with flag", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id)
      assert {:ok, got} = Documents.get_document(srv, doc.id, include_deleted: true)
      assert got.deleted_at != nil
    end