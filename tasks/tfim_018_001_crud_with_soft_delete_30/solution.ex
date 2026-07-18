    test "double restore is idempotent", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      post(conn, ~p"/api/documents/#{doc.id}/restore")
      conn2 = post(conn, ~p"/api/documents/#{doc.id}/restore")

      assert conn2.status == 200
      assert json_data(conn2)["deleted_at"] == nil
    end