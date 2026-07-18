    test "404 for missing", %{srv: srv} do
      assert {:error, :not_found} = Documents.restore_document(srv, 999, 0)
    end