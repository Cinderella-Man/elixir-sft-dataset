    test "price is required and must be positive", %{conn: conn} do
      items = [
        # missing price
        %{"name" => "A"},
        # zero
        %{"name" => "B", "price" => 0},
        # negative
        %{"name" => "C", "price" => -10}
      ]

      conn = bulk_create(conn, items)
      body = json_response(conn, 422)

      for entry <- body["errors"], is_map(entry["errors"]) do
        assert Map.has_key?(entry["errors"], "price")
      end
    end