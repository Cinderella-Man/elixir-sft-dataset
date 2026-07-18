  test "string-keyed attrs are accepted by create and update", %{srv: srv} do
    assert {:ok, doc} = Documents.create_document(srv, %{"title" => "S", "content" => "C"})
    assert doc.title == "S"
    assert doc.content == "C"
    assert doc.lock_version == 0

    assert {:ok, up} = Documents.update_document(srv, doc.id, %{"content" => "C2"}, 0)
    assert up.content == "C2"
    assert up.title == "S"
    assert up.lock_version == 1
  end