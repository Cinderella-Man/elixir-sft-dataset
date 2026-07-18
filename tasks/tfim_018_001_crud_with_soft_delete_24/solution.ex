    test "restores a soft-deleted document", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      conn = post(conn, ~p"/api/documents/#{doc.id}/restore")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] == nil
    end