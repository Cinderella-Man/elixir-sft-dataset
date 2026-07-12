    test "returns all errors when every item is invalid in partial mode", %{conn: conn} do
      items = [
        %{"name" => "", "price" => -1},
        %{"price" => 0}
      ]

      conn = bulk_create(conn, items, partial: true)
      body = json_response(conn, 201)

      assert body["status"] == "partial"
      assert body["created"] == []
      assert length(body["errors"]) == 2
      assert Repo.aggregate(Item, :count) == 0
    end