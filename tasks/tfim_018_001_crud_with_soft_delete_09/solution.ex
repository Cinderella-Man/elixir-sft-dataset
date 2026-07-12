    test "include_deleted=false behaves like default", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      conn = get(conn, ~p"/api/documents?include_deleted=false")
      data = json_response(conn, 200)["data"]
      assert data == []
    end