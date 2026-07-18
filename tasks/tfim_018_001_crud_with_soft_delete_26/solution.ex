    test "restoring a non-deleted document is a no-op 200", %{conn: conn} do
      doc = create_document()

      conn = post(conn, ~p"/api/documents/#{doc.id}/restore")
      assert conn.status == 200

      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] == nil
    end