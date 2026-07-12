    test "returns 422 when title is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"content" => "Hello"}
        })

      errors = json_errors(conn, 422)
      assert errors["title"]
    end