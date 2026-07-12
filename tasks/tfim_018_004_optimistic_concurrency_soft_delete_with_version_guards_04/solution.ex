    test "hides soft-deleted by default", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id, 0)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id)
      assert {:ok, _} = Documents.get_document(srv, doc.id, include_deleted: true)
    end