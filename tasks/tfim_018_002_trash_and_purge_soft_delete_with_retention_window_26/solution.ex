    test "purge_expired removes only expired documents", %{srv: srv, advance: advance} do
      a = create(srv, %{title: "keep-active"})
      b = create(srv, %{title: "recent-trash"})
      c = create(srv, %{title: "old-trash"})
      {:ok, _} = Documents.soft_delete_document(srv, c.id)
      advance.(1000)
      {:ok, _} = Documents.soft_delete_document(srv, b.id)

      assert {:ok, 1} = Documents.purge_expired(srv)

      ids = Documents.list_documents(srv, include_deleted: true) |> Enum.map(& &1.id)
      assert a.id in ids
      assert b.id in ids
      refute c.id in ids
    end