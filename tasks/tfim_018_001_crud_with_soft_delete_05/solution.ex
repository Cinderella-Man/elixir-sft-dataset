    test "returns 422 when content is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "A Title"}
        })

      errors = json_errors(conn, 422)
      assert errors["content"]
    end