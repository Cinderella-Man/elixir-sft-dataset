    test "returns 422 when title is empty string", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "", "content" => "Hello"}
        })

      errors = json_errors(conn, 422)
      assert errors["title"]
    end