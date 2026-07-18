    test "single invalid item returns 422", %{conn: conn} do
      conn = bulk_create(conn, [%{"name" => ""}])
      body = json_response(conn, 422)

      assert body["status"] == "all_failed"
      assert Repo.aggregate(Item, :count) == 0
    end