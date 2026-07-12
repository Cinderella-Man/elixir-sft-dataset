    test "returns all documents when include_deleted=true", %{conn: conn} do
      doc1 = create_document(%{title: "Visible"})
      doc2 = create_document(%{title: "Deleted"})
      soft_delete!(doc2)

      conn = get(conn, ~p"/api/documents?include_deleted=true")
      data = json_response(conn, 200)["data"]

      ids = Enum.map(data, & &1["id"])
      assert doc1.id in ids
      assert doc2.id in ids
    end