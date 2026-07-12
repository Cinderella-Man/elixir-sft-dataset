    test "returns active document", %{srv: srv} do
      doc = create(srv)
      assert {:ok, got} = Documents.get_document(srv, doc.id)
      assert got.id == doc.id
    end