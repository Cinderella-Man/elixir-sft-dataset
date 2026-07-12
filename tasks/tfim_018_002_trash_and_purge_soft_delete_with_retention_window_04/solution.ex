    test "rejects empty title", %{srv: srv} do
      assert {:error, errors} = Documents.create_document(srv, %{title: "", content: "Hello"})
      assert errors[:title]
    end