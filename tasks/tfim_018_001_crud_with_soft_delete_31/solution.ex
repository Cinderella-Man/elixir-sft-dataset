    test "deleted_at timestamp is a valid ISO8601 datetime", %{conn: conn} do
      doc = create_document()
      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      deleted_at = json_data(conn)["deleted_at"]

      assert {:ok, _dt, _offset} = DateTime.from_iso8601(deleted_at)
    end