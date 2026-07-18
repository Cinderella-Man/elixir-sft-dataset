    test "stale version rejected", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id, 0)
      assert {:error, :stale_version, 1} = Documents.restore_document(srv, doc.id, 0)
    end