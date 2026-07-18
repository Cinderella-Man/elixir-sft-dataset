    test "handles a larger batch correctly", %{conn: conn} do
      valid_items = Enum.map(1..50, fn i -> valid_attrs(%{"name" => "Item #{i}"}) end)

      conn = bulk_create(conn, valid_items)
      body = json_response(conn, 201)

      assert body["status"] == "all_created"
      assert length(body["items"]) == 50
      assert Repo.aggregate(Item, :count) == 50
    end