    test "rejects missing content", %{srv: srv} do
      assert {:error, errors} = Documents.create_document(srv, %{title: "A"})
      assert errors[:content]
    end