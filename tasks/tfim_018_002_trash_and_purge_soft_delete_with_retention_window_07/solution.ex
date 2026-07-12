    test "empty by default", %{srv: srv} do
      assert Documents.list_documents(srv) == []
    end