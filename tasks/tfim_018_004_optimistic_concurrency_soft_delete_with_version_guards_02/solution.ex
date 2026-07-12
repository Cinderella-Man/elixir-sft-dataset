    test "creates with version 0", %{srv: srv} do
      {:ok, doc} = Documents.create_document(srv, %{title: "A", content: "B"})
      assert doc.lock_version == 0
      assert doc.deleted_at == nil
    end