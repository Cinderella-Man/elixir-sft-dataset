  test "returns empty data when page exceeds total_pages", %{conn: conn} do
    seed_items(5)

    conn = get(conn, "/api/items", %{"page" => "999", "page_size" => "10"})
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert data == []
    assert meta["current_page"] == 999
    assert meta["total_count"] == 5
    assert meta["total_pages"] == 1
  end