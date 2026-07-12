    test "accepts string keys", %{srv: srv} do
      assert {:ok, doc} = Documents.create_document(srv, %{"title" => "S", "content" => "K"})
      assert doc.title == "S"
    end