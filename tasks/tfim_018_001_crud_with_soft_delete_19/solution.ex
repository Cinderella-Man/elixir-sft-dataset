    test "cannot set deleted_at through update", %{conn: conn} do
      doc = create_document()

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"deleted_at" => DateTime.to_iso8601(DateTime.utc_now())}
        })

      data = json_data(conn)
      assert data["deleted_at"] == nil
    end