    test "404 for missing and for soft-deleted", %{srv: srv} do
      assert {:error, :not_found} = Documents.update_document(srv, 999, %{title: "x"}, 0)
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id, 0)
      assert {:error, :not_found} = Documents.update_document(srv, doc.id, %{title: "x"}, 1)
    end