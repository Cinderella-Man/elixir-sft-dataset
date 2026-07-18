  test "update of a soft-deleted doc reports not_found even when version is stale", %{srv: srv} do
    doc = create(srv)
    {:ok, _} = Documents.soft_delete_document(srv, doc.id, 0)

    assert {:error, :not_found} = Documents.update_document(srv, doc.id, %{title: "x"}, 0)
  end