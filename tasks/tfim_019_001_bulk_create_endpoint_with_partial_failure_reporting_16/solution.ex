    test "single valid item works", %{conn: conn} do
      conn = bulk_create(conn, [valid_attrs()])
      body = json_response(conn, 201)

      assert body["status"] == "all_created"
      assert length(body["items"]) == 1
      assert Repo.aggregate(Item, :count) == 1
    end