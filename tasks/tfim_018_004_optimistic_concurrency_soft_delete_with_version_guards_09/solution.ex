    test "invalid attrs rejected after version check", %{srv: srv} do
      doc = create(srv)
      assert {:error, e} = Documents.update_document(srv, doc.id, %{title: ""}, 0)
      assert e[:title]
    end