  test "each item in data has the required fields", %{conn: conn} do
    seed_items(1)

    conn = get(conn, "/api/items")
    assert %{"data" => [item]} = json_response(conn, 200)

    assert Map.has_key?(item, "id")
    assert Map.has_key?(item, "name")
    assert Map.has_key?(item, "inserted_at")
  end