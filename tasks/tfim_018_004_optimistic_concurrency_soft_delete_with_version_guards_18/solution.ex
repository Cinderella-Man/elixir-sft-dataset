    test "not-deleted rejected", %{srv: srv} do
      doc = create(srv)
      assert {:error, :not_deleted} = Documents.restore_document(srv, doc.id, 0)
    end