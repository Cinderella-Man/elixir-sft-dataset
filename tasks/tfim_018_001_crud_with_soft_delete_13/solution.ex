    test "returns soft-deleted document when include_deleted=true", %{conn: conn} do
      doc = create_document(%{title: "Ghost"})
      soft_delete!(doc)

      conn = get(conn, ~p"/api/documents/#{doc.id}?include_deleted=true")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["title"] == "Ghost"
      assert data["deleted_at"] != nil
    end