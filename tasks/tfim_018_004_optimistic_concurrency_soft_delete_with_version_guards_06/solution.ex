    test "succeeds with matching version and bumps it", %{srv: srv} do
      doc = create(srv, %{title: "old"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "new"}, 0)
      assert up.title == "new"
      assert up.lock_version == 1
    end