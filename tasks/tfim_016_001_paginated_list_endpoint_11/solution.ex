  test "page of 0 or negative is treated as page 1", %{conn: conn} do
    seed_items(5)

    conn = get(conn, "/api/items", %{"page" => "0"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["current_page"] == 1

    conn = get(conn, "/api/items", %{"page" => "-3"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["current_page"] == 1
  end