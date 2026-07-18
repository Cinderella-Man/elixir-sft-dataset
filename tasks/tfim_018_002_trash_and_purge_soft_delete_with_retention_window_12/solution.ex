    test "updates title and content", %{srv: srv} do
      doc = create(srv, %{title: "Old", content: "Old"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "New", content: "New!"})
      assert up.title == "New"
      assert up.content == "New!"
    end