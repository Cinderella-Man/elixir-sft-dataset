    test "returns a document by id", %{conn: conn} do
      doc = create_document(%{title: "Fetchable"})
      conn = get(conn, ~p"/api/documents/#{doc.id}")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["title"] == "Fetchable"
    end