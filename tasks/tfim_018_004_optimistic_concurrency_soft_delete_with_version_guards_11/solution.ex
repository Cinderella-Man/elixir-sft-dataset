    test "cannot set deleted_at via update", %{srv: srv} do
      doc = create(srv)
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "X", deleted_at: 99}, 0)
      assert up.deleted_at == nil
    end