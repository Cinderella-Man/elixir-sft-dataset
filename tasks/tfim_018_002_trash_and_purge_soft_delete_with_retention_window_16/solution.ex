    test "cannot set deleted_at through update", %{srv: srv} do
      doc = create(srv)
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "X", deleted_at: 12345})
      assert up.deleted_at == nil
    end