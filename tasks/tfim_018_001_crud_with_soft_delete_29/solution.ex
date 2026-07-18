    test "multiple documents — deleting one doesn't affect others", %{conn: conn} do
      _doc1 = create_document(%{title: "Keep"})
      doc2 = create_document(%{title: "Remove"})
      _doc3 = create_document(%{title: "Also Keep"})

      soft_delete!(doc2)

      conn = get(conn, ~p"/api/documents")
      titles = Enum.map(json_response(conn, 200)["data"], & &1["title"])

      assert "Keep" in titles
      assert "Also Keep" in titles
      refute "Remove" in titles
    end