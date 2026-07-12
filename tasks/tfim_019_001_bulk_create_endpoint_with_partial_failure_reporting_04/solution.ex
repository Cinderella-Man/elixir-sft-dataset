    test "creates all items when every item is valid", %{conn: conn} do
      items = [
        valid_attrs(%{"name" => "Alpha", "price" => 10}),
        valid_attrs(%{"name" => "Beta", "price" => 20}),
        valid_attrs(%{"name" => "Gamma", "price" => 30})
      ]

      conn = bulk_create(conn, items)
      body = json_response(conn, 201)

      assert body["status"] == "all_created"
      assert length(body["items"]) == 3

      # Each returned item has an index, an id, and the correct fields
      for {returned, idx} <- Enum.with_index(body["items"]) do
        assert returned["index"] == idx
        assert is_integer(returned["id"])
        assert returned["name"] == Enum.at(items, idx)["name"]
        assert returned["price"] == Enum.at(items, idx)["price"]
      end

      # Verify database state
      assert Repo.aggregate(Item, :count) == 3
    end