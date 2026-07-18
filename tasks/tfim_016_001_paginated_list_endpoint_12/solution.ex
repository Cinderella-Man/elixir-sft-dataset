  test "non-numeric params fall back to defaults", %{conn: conn} do
    seed_items(5)

    conn = get(conn, "/api/items", %{"page" => "abc", "page_size" => "xyz"})
    assert %{"meta" => meta} = json_response(conn, 200)

    assert meta["current_page"] == 1
    assert meta["page_size"] == 20
  end