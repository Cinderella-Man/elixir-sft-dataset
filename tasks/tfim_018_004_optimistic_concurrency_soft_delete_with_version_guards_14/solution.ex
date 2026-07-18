    test "already deleted rejected", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id, 0)

      assert {:error, :already_deleted} =
               Documents.soft_delete_document(srv, doc.id, del.lock_version)
    end