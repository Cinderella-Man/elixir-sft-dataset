    test "404 for missing id", %{srv: srv} do
      assert {:error, :not_found} = Documents.get_document(srv, 999)
    end