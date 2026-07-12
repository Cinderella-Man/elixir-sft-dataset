    test "rejects missing title", %{srv: srv} do
      assert {:error, errors} = Documents.create_document(srv, %{content: "Hello"})
      assert errors[:title]
    end