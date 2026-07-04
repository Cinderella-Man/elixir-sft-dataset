  test "returns empty data and zero total_pages when no items exist", %{conn: conn} do
    conn = get(conn, "/api/items")
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert data == []
    assert meta["current_page"] == 1
    assert meta["page_size"] == 20
    assert meta["total_count"] == 0
    assert meta["total_pages"] == 0
  end