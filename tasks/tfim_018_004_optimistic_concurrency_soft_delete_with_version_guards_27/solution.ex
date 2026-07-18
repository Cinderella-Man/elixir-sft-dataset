  test "create rejects blank content and stores nothing", %{srv: srv} do
    assert {:error, e} = Documents.create_document(srv, %{title: "A", content: ""})
    assert e[:content]
    assert Documents.list_documents(srv, include_deleted: true) == []
  end