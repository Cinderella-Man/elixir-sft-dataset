    test "partial update keeps other field", %{srv: srv} do
      doc = create(srv, %{title: "old", content: "keep"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "new"}, 0)
      assert up.content == "keep"
    end