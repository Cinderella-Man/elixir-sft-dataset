  test "total_pages rounds up for non-exact divisions", %{conn: conn} do
    seed_items(21)

    conn = get(conn, "/api/items", %{"page_size" => "10"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["total_pages"] == 3
  end