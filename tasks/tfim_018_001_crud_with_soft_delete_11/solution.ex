    test "returns 404 for non-existent id", %{conn: conn} do
      conn = get(conn, ~p"/api/documents/0")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end