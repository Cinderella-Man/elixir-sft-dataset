    test "empty list creates nothing and returns success", %{conn: conn} do
      conn = bulk_create(conn, [])
      body = json_response(conn, 201)

      assert body["status"] == "all_created"
      assert body["items"] == []
      assert Repo.aggregate(Item, :count) == 0
    end