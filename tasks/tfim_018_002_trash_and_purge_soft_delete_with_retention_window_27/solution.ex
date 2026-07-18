    test "create -> trash -> expire -> purge", %{srv: srv, advance: advance} do
      doc = create(srv, %{title: "Life", content: "v1"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{content: "v2"})
      assert up.content == "v2"

      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id)

      advance.(1000)
      assert {:error, :expired} = Documents.restore_document(srv, doc.id)

      assert {:ok, 1} = Documents.purge_expired(srv)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id, include_deleted: true)
    end