    test "creates with valid attrs", %{srv: srv} do
      {:ok, doc} = Documents.create_document(srv, %{title: "My Doc", content: "Hello"})
      assert doc.id
      assert doc.title == "My Doc"
      assert doc.content == "Hello"
      assert doc.deleted_at == nil
      assert is_integer(doc.inserted_at)
      assert is_integer(doc.updated_at)
    end