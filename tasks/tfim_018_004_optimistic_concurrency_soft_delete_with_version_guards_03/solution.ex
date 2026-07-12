    test "rejects blank fields", %{srv: srv} do
      assert {:error, e} = Documents.create_document(srv, %{title: "", content: "B"})
      assert e[:title]
    end