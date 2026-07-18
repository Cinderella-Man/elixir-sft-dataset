  test "rejected stale update leaves the stored document untouched", %{srv: srv} do
    doc = create(srv, %{title: "keep", content: "same"})
    {:ok, _} = Documents.update_document(srv, doc.id, %{title: "v1"}, 0)

    assert {:error, :stale_version, 1} =
             Documents.update_document(srv, doc.id, %{title: "v2", content: "other"}, 0)

    assert {:ok, cur} = Documents.get_document(srv, doc.id)
    assert cur.title == "v1"
    assert cur.content == "same"
    assert cur.lock_version == 1
  end