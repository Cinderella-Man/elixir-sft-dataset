    test "description is accepted when within limits", %{conn: conn} do
      items = [valid_attrs(%{"description" => String.duplicate("x", 1000)})]

      conn = bulk_create(conn, items)
      body = json_response(conn, 201)

      assert body["status"] == "all_created"
      assert hd(body["items"])["description"] == String.duplicate("x", 1000)
    end