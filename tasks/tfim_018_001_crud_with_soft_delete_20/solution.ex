    test "soft-deletes a document (sets deleted_at)", %{conn: conn} do
      doc = create_document()

      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      data = json_data(conn)
      assert data["id"] == doc.id
      assert data["deleted_at"] != nil
    end