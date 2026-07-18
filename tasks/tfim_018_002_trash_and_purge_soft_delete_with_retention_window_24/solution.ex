    test "purge_document refuses an active doc", %{srv: srv} do
      doc = create(srv)
      assert {:error, :not_deleted} = Documents.purge_document(srv, doc.id)
    end