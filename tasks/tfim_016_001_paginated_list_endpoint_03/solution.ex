  test "respects page and page_size params", %{conn: conn} do
    seed_items(15)

    conn = get(conn, "/api/items", %{"page" => "2", "page_size" => "5"})
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert length(data) == 5
    assert meta["current_page"] == 2
    assert meta["page_size"] == 5
    assert meta["total_count"] == 15
    assert meta["total_pages"] == 3
  end