    test "list excludes deleted by default", %{srv: srv} do
      a = create(srv, %{title: "keep"})
      b = create(srv, %{title: "gone"})
      {:ok, _} = Documents.soft_delete_document(srv, b.id, 0)
      ids = Documents.list_documents(srv) |> Enum.map(& &1.id)
      assert a.id in ids
      refute b.id in ids
    end