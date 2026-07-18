  test "total_pages is correct for exact divisions", %{conn: conn} do
    seed_items(20)

    conn = get(conn, "/api/items", %{"page_size" => "10"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["total_pages"] == 2
  end