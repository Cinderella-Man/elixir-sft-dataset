    test "description is optional but capped at 1000 chars", %{conn: conn} do
      long_desc = String.duplicate("x", 1001)

      items = [
        valid_attrs(%{"description" => long_desc})
      ]

      conn = bulk_create(conn, items)
      body = json_response(conn, 422)

      failed = List.first(body["errors"])
      assert Map.has_key?(failed["errors"], "description")
    end