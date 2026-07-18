    test "expired document cannot be restored", %{srv: srv, advance: advance} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      advance.(1000)
      assert {:error, :expired} = Documents.restore_document(srv, doc.id)
      # still visible with include_deleted until purged
      assert {:ok, _} = Documents.get_document(srv, doc.id, include_deleted: true)
    end