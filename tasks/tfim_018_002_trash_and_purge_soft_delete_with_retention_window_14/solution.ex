    test "rejects empty title", %{srv: srv} do
      doc = create(srv)
      assert {:error, errors} = Documents.update_document(srv, doc.id, %{title: ""})
      assert errors[:title]
    end