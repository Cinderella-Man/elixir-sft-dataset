  test "clamps page_size to 100 when a larger value is given", %{conn: conn} do
    seed_items(150)

    conn = get(conn, "/api/items", %{"page_size" => "500"})
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert length(data) == 100
    assert meta["page_size"] == 100
    assert meta["total_count"] == 150
    assert meta["total_pages"] == 2
  end