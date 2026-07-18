    test "partial=false is treated as all-or-nothing", %{conn: conn} do
      items = [valid_attrs(), %{"name" => ""}]

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/items/bulk?partial=false", Jason.encode!(%{"items" => items}))

      body = json_response(conn, 422)

      assert body["status"] == "all_failed"
      assert Repo.aggregate(Item, :count) == 0
    end