  test "list with include_deleted: true returns every document sorted by id", %{srv: srv} do
    a = create(srv, %{title: "a"})
    b = create(srv, %{title: "b"})
    c = create(srv, %{title: "c"})
    {:ok, _} = Documents.soft_delete_document(srv, b.id, 0)

    ids =
      srv
      |> Documents.list_documents(include_deleted: true)
      |> Enum.map(& &1.id)

    assert ids == [a.id, b.id, c.id]
    assert ids == Enum.sort(ids)
  end