    test "soft-deleted document disappears from default listings", %{conn: conn} do
      doc = create_document()

      delete(conn, ~p"/api/documents/#{doc.id}")

      conn = get(conn, ~p"/api/documents")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      refute doc.id in ids
    end