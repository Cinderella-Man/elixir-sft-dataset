  test "page 2 does not repeat items from page 1", %{conn: conn} do
    seed_items(10)

    conn1 = get(conn, "/api/items", %{"page" => "1", "page_size" => "5"})
    conn2 = get(conn, "/api/items", %{"page" => "2", "page_size" => "5"})

    %{"data" => page1} = json_response(conn1, 200)
    %{"data" => page2} = json_response(conn2, 200)

    page1_ids = MapSet.new(page1, & &1["id"])
    page2_ids = MapSet.new(page2, & &1["id"])

    assert MapSet.disjoint?(page1_ids, page2_ids)
    assert MapSet.size(page1_ids) == 5
    assert MapSet.size(page2_ids) == 5
  end