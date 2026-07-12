    test "returns 400 when 'items' key is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/items/bulk", Jason.encode!(%{"stuff" => []}))

      assert json_response(conn, 400)["error"] == "expected a list of items"
    end