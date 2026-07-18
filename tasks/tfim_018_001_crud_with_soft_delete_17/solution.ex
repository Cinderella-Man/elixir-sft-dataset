    test "returns 404 for non-existent document", %{conn: conn} do
      conn =
        put(conn, ~p"/api/documents/0", %{
          "document" => %{"title" => "Nope"}
        })

      assert json_errors(conn, 404)["detail"] == "Not found"
    end