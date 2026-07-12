    test "returns empty list when no documents exist", %{conn: conn} do
      conn = get(conn, ~p"/api/documents")
      assert json_response(conn, 200)["data"] == []
    end