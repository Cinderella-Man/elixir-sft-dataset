    test "created items can be fetched from the database", %{conn: conn} do
      items = [
        valid_attrs(%{"name" => "Persisted", "price" => 42, "description" => "check me"})
      ]

      conn = bulk_create(conn, items)
      body = json_response(conn, 201)

      id = hd(body["items"])["id"]
      db_item = Repo.get!(Item, id)

      assert db_item.name == "Persisted"
      assert db_item.price == 42
      assert db_item.description == "check me"
    end