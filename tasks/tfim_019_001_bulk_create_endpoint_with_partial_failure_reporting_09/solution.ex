    test "returns all created when every item is valid in partial mode", %{conn: conn} do
      items = [
        valid_attrs(%{"name" => "A"}),
        valid_attrs(%{"name" => "B"})
      ]

      conn = bulk_create(conn, items, partial: true)
      body = json_response(conn, 201)

      assert body["status"] == "partial"
      assert length(body["created"]) == 2
      assert body["errors"] == []
      assert Repo.aggregate(Item, :count) == 2
    end