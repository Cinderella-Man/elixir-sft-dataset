    test "name is required and must be 1-255 chars", %{conn: conn} do
      long_name = String.duplicate("a", 256)

      items = [
        # missing name
        %{"price" => 10},
        # blank name
        %{"name" => "", "price" => 10},
        # too long
        %{"name" => long_name, "price" => 10}
      ]

      conn = bulk_create(conn, items)
      body = json_response(conn, 422)

      for entry <- body["errors"], is_map(entry["errors"]) do
        assert Map.has_key?(entry["errors"], "name")
      end
    end