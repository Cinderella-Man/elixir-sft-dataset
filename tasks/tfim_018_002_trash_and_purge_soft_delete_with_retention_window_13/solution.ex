    test "partial update keeps other field", %{srv: srv} do
      doc = create(srv, %{title: "Old", content: "Keep"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "New"})
      assert up.title == "New"
      assert up.content == "Keep"
    end