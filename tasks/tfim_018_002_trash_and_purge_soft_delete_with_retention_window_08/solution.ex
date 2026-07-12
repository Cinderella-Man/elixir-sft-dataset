    test "excludes trashed by default, includes with flag", %{srv: srv} do
      a = create(srv, %{title: "Visible"})
      b = create(srv, %{title: "Trashed"})
      {:ok, _} = Documents.soft_delete_document(srv, b.id)

      default_ids = Documents.list_documents(srv) |> Enum.map(& &1.id)
      assert a.id in default_ids
      refute b.id in default_ids

      all_ids = Documents.list_documents(srv, include_deleted: true) |> Enum.map(& &1.id)
      assert a.id in all_ids
      assert b.id in all_ids
    end