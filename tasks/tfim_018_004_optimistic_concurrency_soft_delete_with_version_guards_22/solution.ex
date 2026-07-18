    test "create -> update -> delete -> restore threading versions", %{srv: srv} do
      doc = create(srv, %{title: "Life", content: "v1"})
      {:ok, a} = Documents.update_document(srv, doc.id, %{content: "v2"}, doc.lock_version)
      {:ok, b} = Documents.soft_delete_document(srv, doc.id, a.lock_version)
      assert b.deleted_at != nil
      {:ok, c} = Documents.restore_document(srv, doc.id, b.lock_version)
      assert c.deleted_at == nil
      assert c.content == "v2"
      assert c.lock_version == 3
    end