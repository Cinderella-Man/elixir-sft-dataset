    test "404 for missing and for trashed", %{srv: srv} do
      assert {:error, :not_found} = Documents.update_document(srv, 999, %{title: "x"})
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      assert {:error, :not_found} = Documents.update_document(srv, doc.id, %{title: "x"})
    end