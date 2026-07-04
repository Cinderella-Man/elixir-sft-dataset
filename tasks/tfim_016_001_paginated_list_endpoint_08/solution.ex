  test "items are returned in deterministic order", %{conn: conn} do
    seed_items(10)

    conn = get(conn, "/api/items", %{"page_size" => "10"})
    assert %{"data" => data} = json_response(conn, 200)

    names = Enum.map(data, & &1["name"])
    assert names == Enum.sort(names)
  end