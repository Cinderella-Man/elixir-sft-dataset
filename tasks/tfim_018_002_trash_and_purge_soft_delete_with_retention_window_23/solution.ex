    test "purge_document hard-deletes a trashed doc", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      assert {:ok, _} = Documents.purge_document(srv, doc.id)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id, include_deleted: true)
    end