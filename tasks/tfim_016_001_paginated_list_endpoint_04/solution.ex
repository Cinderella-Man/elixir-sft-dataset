  test "last page returns only remaining items", %{conn: conn} do
    seed_items(12)

    conn = get(conn, "/api/items", %{"page" => "3", "page_size" => "5"})
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert length(data) == 2
    assert meta["current_page"] == 3
    assert meta["total_pages"] == 3
  end