  test "returns first page with default page_size when no params given", %{conn: conn} do
    seed_items(25)

    conn = get(conn, "/api/items")
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert length(data) == 20
    assert meta["current_page"] == 1
    assert meta["page_size"] == 20
    assert meta["total_count"] == 25
    assert meta["total_pages"] == 2
  end