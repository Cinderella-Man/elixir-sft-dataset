    test "returns 400 when 'items' is not a list", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/items/bulk", Jason.encode!(%{"items" => "not_a_list"}))

      assert json_response(conn, 400)["error"] == "expected a list of items"
    end