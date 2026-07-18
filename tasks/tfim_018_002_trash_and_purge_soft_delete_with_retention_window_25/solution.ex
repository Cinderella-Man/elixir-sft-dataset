    test "purge_document 404 for missing", %{srv: srv} do
      assert {:error, :not_found} = Documents.purge_document(srv, 999)
    end