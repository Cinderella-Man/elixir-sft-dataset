  test "page_size of 0 or negative is treated as default", %{conn: conn} do
    seed_items(5)

    conn = get(conn, "/api/items", %{"page_size" => "0"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["page_size"] == 20

    conn = get(conn, "/api/items", %{"page_size" => "-5"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["page_size"] == 20
  end